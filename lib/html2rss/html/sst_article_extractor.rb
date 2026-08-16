# frozen_string_literal: true

require 'zlib'

module Html2rss
  module Html
    ##
    # Builds an {Html2rss::Article} from an SST segment / ranked segment.
    # Port of Html::ArticleExtractor field logic onto SST::Node.
    # rubocop:disable Metrics/ClassLength -- SST field extractors colocated for parity with ArticleExtractor
    class SstArticleExtractor
      # CSS class tokens that mark kicker / eyebrow text (excluded from titles).
      KICKER_CLASS_PATTERN = /kicker|eyebrow|pre-title|pretitle|overline/i
      # Inline emphasis tags used as title fallbacks when no heading exists.
      FALLBACK_HEADING_NAMES = %i[strong b].freeze

      class << self
        ##
        # @param ranked_or_segment [Scoring::RankedSegment, AutoSource::Segment]
        # @param base_url [String, Html2rss::Url]
        # @param scraper [Class, nil]
        # @param fallback_anchorless [Boolean]
        # @return [Html2rss::Article, nil]
        def call(ranked_or_segment, base_url:, scraper: nil, fallback_anchorless: false)
          new(ranked_or_segment, base_url:, scraper:, fallback_anchorless:).call
        end
      end

      # @param ranked_or_segment [Scoring::RankedSegment, AutoSource::Segment]
      # @param base_url [String, Html2rss::Url]
      # @param scraper [Class, nil]
      # @param fallback_anchorless [Boolean]
      def initialize(ranked_or_segment, base_url:, scraper: nil, fallback_anchorless: false)
        segment = ranked_or_segment.is_a?(Scoring::RankedSegment) ? ranked_or_segment.segment : ranked_or_segment
        raise ArgumentError, 'segment is required' unless segment.is_a?(AutoSource::Segment)

        @segment = segment
        @root = segment.root_node
        @selected_anchor = segment.primary_link
        @base_url = base_url
        @scraper = scraper
        @fallback_anchorless = fallback_anchorless
      end

      ##
      # @return [Html2rss::Article, nil]
      def call # rubocop:disable Metrics/MethodLength
        attrs = {
          title: extract_title,
          url: extract_url,
          image: extract_image,
          description: extract_description,
          id: generate_id,
          published_at: extract_published_at,
          enclosures: extract_enclosures,
          categories: extract_categories,
          scraper: @scraper
        }
        article = Article.new(**attrs)
        article.valid? ? article : nil
      end

      private

      def extract_url
        @extract_url ||= begin
          href = @selected_anchor&.attrs&.href.to_s
          if href.empty?
            anchorless_url_fallback
          else
            Url.from_relative(href.split('#').first.strip, @base_url)
          end
        end
      end

      def anchorless_url_fallback
        return unless @fallback_anchorless

        id = generate_id
        Url.from_relative("##{id}", @base_url) if id
      end

      def extract_title
        title_text = title_from_in_card_sources
        return unless title_text

        kicker = kicker_node&.visible_text.to_s.strip
        kicker && !kicker.empty? && !title_text.include?(kicker) ? "#{kicker}: #{title_text}" : title_text
      end

      # Prefer heading over credit-shaped visible text; never emit agency-only titles.
      #
      # @return [String, nil]
      def title_from_in_card_sources
        title_candidates.find { |text| AutoSource::Cleanup.junk_reason(text).nil? }
      end

      # @return [Array<String>] ordered in-card title candidates (heading → anchor → fallback)
      def title_candidates
        [].tap do |candidates|
          add_title_candidate!(candidates, heading&.visible_text)
          add_title_candidate!(candidates, @selected_anchor&.visible_text)
          next unless candidates.empty? && @fallback_anchorless && @selected_anchor.nil?

          add_title_candidate!(candidates, first_nonempty_own_text)
        end
      end

      # @param candidates [Array<String>]
      # @param text [String, nil]
      # @return [void]
      def add_title_candidate!(candidates, text)
        stripped = text.to_s.strip
        return if stripped.empty? || candidates.include?(stripped)

        candidates << stripped
      end

      def heading
        @heading ||= begin
          tags = @root.find_all(&:heading?)
          if tags.any?
            select_best_heading(tags)
          elsif @fallback_anchorless && @selected_anchor.nil?
            fallback_heading
          end
        end
      end

      def select_best_heading(tags)
        min_name = tags.map { |t| t.name.to_s }.min
        best = nil
        max_size = -1
        tags.each do |tag|
          next unless tag.name.to_s == min_name

          size = tag.visible_text.to_s.size
          (best = tag) && (max_size = size) if size > max_size
        end
        best
      end

      def fallback_heading
        @root.find do |n|
          next true if FALLBACK_HEADING_NAMES.include?(n.name)

          n.attrs.class_names.any? { |c| c.match?(/title|font-bold|font-semibold/) } &&
            !n.visible_text.to_s.strip.empty?
        end
      end

      def kicker_node # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        @kicker_node ||= begin
          node = @root.find do |n|
            n.attrs.raw.key?('data-tb-kicker') ||
              n.attrs.class_names.any? { |c| c.match?(KICKER_CLASS_PATTERN) }
          end
          node && heading && (node.equal?(heading) || descendant_of?(node, heading)) ? nil : node
        end
      end

      def descendant_of?(child, ancestor)
        # Walk via root children since Extractor may not hold Index; use tag walk on tree.
        return true if child.equal?(ancestor)

        ancestor.descendants.any? { |d| d.equal?(child) }
      end

      def extract_description
        exclude = [heading, @selected_anchor, kicker_node].compact
        description = @root.visible_text(exclude:)
        return if description.nil?

        desc = description.strip
        desc.empty? ? nil : desc
      end

      def generate_id # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
        @generate_id ||= begin
          id_from_dom = parse_id_from_dom
          if id_from_dom
            id_from_dom
          else
            heading_text = heading&.visible_text
            heading_text = first_nonempty_own_text if heading_text.to_s.strip.empty? && @fallback_anchorless
            if heading_text && !heading_text.strip.empty?
              generate_slug(heading_text)
            elsif @fallback_anchorless
              text = @root.visible_text.to_s.strip
              Zlib.crc32(text).to_s(36) unless text.empty?
            end
          end
        end
      end

      def parse_id_from_dom
        candidates = [@root.attrs.id]
        nested = @root.find { |n| n.attrs.id }
        candidates << nested.attrs.id if nested
        if @selected_anchor
          url = extract_url
          candidates += [url&.path, url&.query]
        end
        candidates.compact.reject(&:empty?).first
      end

      def generate_slug(text)
        slug = text.downcase.gsub(/[^a-z0-9]+/, '-')
        slug = slug[1..] if slug.start_with?('-')
        slug = slug[0..-2] if slug.end_with?('-')
        slug unless slug.empty?
      end

      def first_nonempty_own_text
        @root.find { |n| !n.own_text.to_s.strip.empty? }&.own_text&.strip
      end

      def extract_image
        img_src = image_from_srcset || image_from_img || image_from_style
        Url.from_relative(img_src, @base_url) if img_src
      end

      def image_from_img
        @root.find { |n| n.image? && n.attrs.src && !n.attrs.src.start_with?('data:') }&.attrs&.src
      end

      def image_from_srcset
        srcsets = @root.find_all { |n| n.attrs.srcset }.map { |n| n.attrs.srcset }
        ArticleRules::Image.largest_from_srcsets(srcsets)
      end

      def image_from_style
        styles = @root.find_all { |n| n.attrs.style&.include?('url') }.map { |n| n.attrs.style }
        ArticleRules::Image.best_from_styles(styles)
      end

      def extract_published_at
        datetimes = @root.find_all { |n| n.attrs.datetime }.map { |n| n.attrs.datetime }
        ArticleRules::Date.earliest(datetimes)
      end

      def extract_enclosures
        @root.find_all { |n| enclosure_node?(n) }.filter_map { |element| enclosure_from(element) }
      end

      def enclosure_node?(node)
        case node.name
        when :img then node.attrs.src && !node.attrs.src.start_with?('data:')
        when :source, :audio, :video, :iframe then node.attrs.src
        when :a then ArticleRules::Enclosure.archive_href?(node.attrs.href)
        else false
        end
      end

      def enclosure_from(element)
        case element.name
        when :img
          ArticleRules::Enclosure.from_image(element.attrs.src, @base_url)
        when :video, :audio, :source
          ArticleRules::Enclosure.from_media(element.attrs.src, element.attrs.type, @base_url)
        when :iframe
          ArticleRules::Enclosure.from_iframe(element.attrs.src, @base_url)
        when :a
          ArticleRules::Enclosure.from_anchor(element.attrs.href, @base_url)
        end
      end

      def extract_categories
        Set.new.tap do |categories|
          @root.find_all { |n| category_candidate?(n) }.each do |element|
            add_category_text!(categories, element) if ArticleRules::Category.class_match?(element.attrs.class_attr)
            element.attrs.raw.each do |name, value|
              next unless ArticleRules::Category.attr_name_match?(name)

              ArticleRules::Category.add_text!(categories, value)
            end
          end
        end.to_a
      end

      def category_candidate?(node)
        ArticleRules::Category.class_match?(node.attrs.class_attr) ||
          node.attrs.raw.keys.any? { |k| ArticleRules::Category.attr_name_match?(k) }
      end

      def add_category_text!(categories, element)
        if element.link?
          ArticleRules::Category.add_text!(categories, element.visible_text)
          return
        end

        anchors = element.find_all(&:link?)
        if anchors.any?
          anchors.each { |a| ArticleRules::Category.add_text!(categories, a.visible_text) }
        else
          ArticleRules::Category.add_split_text!(categories, element.visible_text)
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
