# frozen_string_literal: true

module Html2rss
  module Test
    ##
    # Probes list-card +enhance+ value on cached HTML (no detail fetch).
    # Sole owner of enhance_gains metrics and enhance-specific warn-only warnings.
    module EnhanceAudit # rubocop:disable Metrics/ModuleLength -- probe + compare + heuristics stay co-located
      module_function

      TRACKED_KEYS = %i[title url description published_at categories author image id enclosures].freeze
      CURATOR_KEYS = %i[title url description published_at].freeze
      private_constant :TRACKED_KEYS, :CURATOR_KEYS

      ##
      # Aggregate enhance probe metrics for one configuration test.
      EnhanceGains = Data.define(:items_probed, :keys_added, :descriptions_added, :no_op)

      ##
      # Probe output merged into {QualityReport}.
      AuditSlice = Data.define(:enhance_gains, :warnings)

      IMAGE_FILENAME = /\.(jpe?g|png|gif|webp|avif|svg)\z/i
      private_constant :IMAGE_FILENAME

      ##
      # @param response [Html2rss::RequestService::Response]
      # @param selectors [Hash{Symbol => Object}]
      # @param time_zone [String]
      # @return [AuditSlice, nil] nil when selectors are absent
      def probe(response:, selectors:, time_zone:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- per-item probe loop
        return nil unless selectors&.dig(:items, :selector)

        selector_engine = Selectors.new(response, selectors:, time_zone:)
        gains = {
          items_probed: 0,
          keys_added: zero_keys_added.dup,
          descriptions_added: 0,
          no_op: true
        }
        warnings = []

        response.parsed_body.css(selector_engine.items_selector).each do |item|
          baseline = selector_engine.extract_article(item, response)
          enhanced = selector_engine.enhance_article_hash(baseline.dup, item, response.url)
          item_keys = keys_added(baseline, enhanced)
          merge_keys_added!(gains, item_keys)
          append_item_warnings!(warnings, item:, enhanced:, item_keys:)
        end

        finalize_gains!(gains)
        warnings << :enhance_no_op if gains.fetch(:no_op)
        AuditSlice.new(
          enhance_gains: EnhanceGains.new(
            items_probed: gains.fetch(:items_probed),
            keys_added: gains.fetch(:keys_added).freeze,
            descriptions_added: gains.fetch(:descriptions_added),
            no_op: gains.fetch(:no_op)
          ),
          warnings: warnings.freeze
        )
      end

      ##
      # @param response [Html2rss::RequestService::Response]
      # @param selectors [Hash{Symbol => Object}]
      # @param time_zone [String]
      # @return [Hash{Symbol => Object}, nil]
      def compare(response:, selectors:, time_zone:) # rubocop:disable Metrics/MethodLength -- enhance off/on stats + delta
        return nil unless selectors&.dig(:items, :selector)

        off = extraction_stats(response, selectors, time_zone, enhance: false)
        on = extraction_stats(response, selectors, time_zone, enhance: true)
        delta_gains = probe(response:, selectors:, time_zone:)&.enhance_gains || empty_gains

        {
          enhance_off: off,
          enhance_on: on,
          delta: {
            descriptions_gained: on[:descriptions_filled] - off[:descriptions_filled],
            keys_added: delta_gains.keys_added,
            no_op: delta_gains.no_op
          }
        }
      end

      ##
      # @return [EnhanceGains] zeroed gains for compare fallback
      def empty_gains
        EnhanceGains.new(
          items_probed: 0,
          keys_added: zero_keys_added,
          descriptions_added: 0,
          no_op: true
        )
      end

      def zero_keys_added
        TRACKED_KEYS.to_h { |key| [key, 0] }.freeze
      end
      private_class_method :zero_keys_added

      def extraction_stats(response, selectors, time_zone, enhance:)
        merged = selectors_with_enhance(selectors, enhance:)
        articles = Selectors.new(response, selectors: merged, time_zone:).articles
        {
          item_count: articles.size,
          descriptions_filled: articles.count { |article| article.description.to_s.strip != '' }
        }
      end
      private_class_method :extraction_stats

      def selectors_with_enhance(selectors, enhance:)
        merged = HashUtil.deep_dup(selectors)
        merged[:items] = merged.fetch(:items, {}).merge(enhance:)
        merged
      end
      private_class_method :selectors_with_enhance

      def keys_added(baseline, enhanced)
        enhanced.each_with_object({}) do |(key, value), counts|
          next if value.nil?

          baseline_value = baseline[key]
          next if baseline.key?(key) && baseline_value

          counts[key] = (counts[key] || 0) + 1
        end
      end
      private_class_method :keys_added

      def merge_keys_added!(gains, item_keys)
        gains[:items_probed] += 1
        item_keys.each do |key, count|
          next unless TRACKED_KEYS.include?(key)

          gains[:keys_added][key] += count
        end
        gains[:descriptions_added] += item_keys.fetch(:description, 0)
      end
      private_class_method :merge_keys_added!

      def finalize_gains!(gains)
        curator_total = CURATOR_KEYS.sum { |key| gains[:keys_added][key] }
        gains[:no_op] = curator_total.zero?
      end
      private_class_method :finalize_gains!

      def append_item_warnings!(warnings, item:, enhanced:, item_keys:)
        curator_added = item_keys.slice(*CURATOR_KEYS)
        return if curator_added.empty?
        return unless curator_added.key?(:description)

        description = enhanced[:description].to_s.strip
        return if description.empty?

        if category_only_description?(description, enhanced)
          warnings << :enhance_category_only_description
        elsif image_only_description?(description, item)
          warnings << :enhance_image_only_description
        end
      end
      private_class_method :append_item_warnings!

      def category_only_description?(description, enhanced)
        normalized = description.downcase
        return true if Html2rss::Html::ArticleRules::Description::TYPE_CHIPS.include?(normalized)

        categories = Array(enhanced[:categories]).map { |category| category.to_s.strip }
        categories.any? { |category| category.casecmp?(description) }
      end
      private_class_method :category_only_description?

      def image_only_description?(description, item)
        images = item.css('img')
        return description == images.first['alt'].to_s.strip if images.size == 1 && images.first['alt']

        prose_shaped?(description) == false
      end
      private_class_method :image_only_description?

      def prose_shaped?(text)
        return false if text.match?(IMAGE_FILENAME)
        return false if text.match?(%r{\Ahttps?://}i)
        return false if text.match?(%r{\A/[\w./-]+\z})

        text.match?(/[a-z]/i)
      end
      private_class_method :prose_shaped?
    end
  end
end
