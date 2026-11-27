# frozen_string_literal: true

module Html2rss
  module Curation
    module Test
      ##
      # Probes list-card +enhance+ value on cached listing HTML.
      # Sole owner of enhance_gains metrics and enhance-specific warn-only warnings.
      module EnhanceAudit # rubocop:disable Metrics/ModuleLength -- probe + compare + heuristics stay co-located
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
        # @param vocabulary [Vocabulary::Scope] the page language's scope, as the feed resolves it
        # @return [AuditSlice, nil] nil when selectors are absent
        def self.probe(response:, selectors:, time_zone:, vocabulary:) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- per-item probe loop
          return nil unless selectors&.dig(:items, :selector)

          selector_engine = Selectors.new(response, selectors:, time_zone:, vocabulary:)
          gains = {
            items_probed: 0,
            keys_added: zero_keys_added.dup,
            descriptions_added: 0,
            no_op: true
          }
          warnings = []

          selector_engine.each_enhance_pair(linked_only: true) do |baseline, enhanced, item|
            item_keys = keys_added(baseline, enhanced)
            merge_keys_added!(gains, item_keys)
            append_item_warnings!(warnings, item:, enhanced:, item_keys:, vocabulary:)
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
        # @param vocabulary [Vocabulary::Scope] the page language's scope, as the feed resolves it
        # @return [Hash{Symbol => Object}, nil]
        def self.compare(response:, selectors:, time_zone:, vocabulary:)
          return nil unless selectors&.dig(:items, :selector)

          off = extracted_articles(response, selectors, time_zone, vocabulary, enhance: false)
          on = extracted_articles(response, selectors, time_zone, vocabulary, enhance: true)
          delta_gains = probe(response:, selectors:, time_zone:, vocabulary:)&.enhance_gains || empty_gains

          off_stats = extraction_stats(off)
          on_stats = extraction_stats(on)

          { enhance_off: off_stats, enhance_on: on_stats, delta: delta(off, on, off_stats, on_stats, delta_gains) }
        end

        def self.delta(off, on, off_stats, on_stats, gains)
          {
            descriptions_gained: on_stats.fetch(:descriptions_filled) - off_stats.fetch(:descriptions_filled),
            guids_changed: (on.map(&:guid) - off.map(&:guid)).size,
            items_added: on.size - off.size,
            keys_added: gains.keys_added,
            no_op: gains.no_op
          }
        end
        private_class_method :delta

        ##
        # @return [EnhanceGains] zeroed gains for compare fallback
        def self.empty_gains
          EnhanceGains.new(
            items_probed: 0,
            keys_added: zero_keys_added,
            descriptions_added: 0,
            no_op: true
          )
        end

        def self.zero_keys_added
          TRACKED_KEYS.to_h { |key| [key, 0] }.freeze
        end
        private_class_method :zero_keys_added

        def self.extracted_articles(response, selectors, time_zone, vocabulary, enhance:)
          merged = selectors_with_enhance(selectors, enhance:)
          Selectors.new(response, selectors: merged, time_zone:, vocabulary:).articles
        end
        private_class_method :extracted_articles

        def self.extraction_stats(articles)
          {
            item_count: articles.size,
            descriptions_filled: articles.count { |article| real_description?(article.description, article.title) }
          }
        end
        private_class_method :extraction_stats

        # A description counts only when it is non-blank and says more than the title.
        def self.real_description?(description, title)
          text = description.to_s.strip
          !text.empty? && text != title.to_s.strip
        end
        private_class_method :real_description?

        def self.present_value?(value)
          case value
          when nil then false
          when String then !value.strip.empty?
          when Array then value.any? { |entry| present_value?(entry) }
          when Hash then value.values.any? { |entry| present_value?(entry) }
          else true
          end
        end
        private_class_method :present_value?

        def self.selectors_with_enhance(selectors, enhance:)
          merged = HashUtil.deep_dup(selectors)
          merged[:items] = merged.fetch(:items, {}).merge(enhance:)
          merged
        end
        private_class_method :selectors_with_enhance

        def self.keys_added(baseline, enhanced)
          enhanced.each_with_object({}) do |(key, value), counts|
            next unless present_value?(value)
            next if present_value?(baseline[key])
            next if key == :description && !real_description?(value, enhanced[:title])

            counts[key] = 1
          end
        end
        private_class_method :keys_added

        def self.merge_keys_added!(gains, item_keys)
          gains[:items_probed] += 1
          item_keys.each do |key, count|
            next unless TRACKED_KEYS.include?(key)

            gains[:keys_added][key] += count
          end
          gains[:descriptions_added] += item_keys.fetch(:description, 0)
        end
        private_class_method :merge_keys_added!

        def self.finalize_gains!(gains)
          curator_total = CURATOR_KEYS.sum { |key| gains[:keys_added][key] }
          gains[:no_op] = curator_total.zero?
        end
        private_class_method :finalize_gains!

        def self.append_item_warnings!(warnings, item:, enhanced:, item_keys:, vocabulary:)
          curator_added = item_keys.slice(*CURATOR_KEYS)
          return if curator_added.empty?
          return unless curator_added.key?(:description)

          description = enhanced[:description].to_s.strip
          return if description.empty?

          if category_only_description?(description, enhanced, vocabulary)
            warnings << :enhance_category_only_description
          elsif image_only_description?(description, item)
            warnings << :enhance_image_only_description
          end
        end
        private_class_method :append_item_warnings!

        def self.category_only_description?(description, enhanced, vocabulary)
          normalized = description.downcase
          return true if vocabulary.type_markers.include?(normalized)

          categories = Array(enhanced[:categories]).map { |category| category.to_s.strip }
          categories.any? { |category| category.casecmp?(description) }
        end
        private_class_method :category_only_description?

        def self.image_only_description?(description, item)
          images = item.css('img')
          return description == images.first['alt'].to_s.strip if images.size == 1 && images.first['alt']

          prose_shaped?(description) == false
        end
        private_class_method :image_only_description?

        def self.prose_shaped?(text)
          return false if text.match?(IMAGE_FILENAME)
          return false if text.match?(%r{\Ahttps?://}i)
          return false if text.match?(%r{\A/[\w./-]+\z})

          text.match?(/[a-z]/i)
        end
        private_class_method :prose_shaped?
      end
    end
  end
end
