# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # ArticleExtractor is responsible for extracting details (headline, url, images, etc.)
    # from an article_tag DOM node. DOM chrome helpers live on {Navigator}.
    class ArticleExtractor
      class << self
        ##
        # Extracts article attributes from a DOM element.
        #
        # @param article_tag [Nokogiri::XML::Node] article-like container to extract from
        # @param base_url [String, Html2rss::Url] base url used to resolve relative links
        # @param selected_anchor [Nokogiri::XML::Node, nil] explicit primary anchor for the container
        # @param fallback_anchorless [Boolean] whether to fall back to anchorless extraction
        # @param time_zone [String] channel time zone for naive leftover dates
        # @return [Hash{Symbol => Object}] extracted article attributes
        def call(article_tag, base_url:, selected_anchor: nil, fallback_anchorless: false, time_zone: 'UTC')
          new(article_tag, base_url:, selected_anchor:, fallback_anchorless:, time_zone:).call
        end
      end

      ##
      # @param article_tag [Nokogiri::XML::Node] article-like container to extract from
      # @param base_url [String, Html2rss::Url] base url used to resolve relative links
      # @param selected_anchor [Nokogiri::XML::Node, nil] explicit primary anchor for the container
      # @param fallback_anchorless [Boolean] whether to fall back to anchorless extraction
      # @param time_zone [String] channel time zone for naive leftover dates
      def initialize(article_tag, base_url:, selected_anchor: nil, fallback_anchorless: false, time_zone: 'UTC')
        raise ArgumentError, 'article_tag is required' unless article_tag

        @article_tag = article_tag
        @base_url = base_url
        @selected_anchor = selected_anchor
        @fallback_anchorless = fallback_anchorless
        @time_zone = time_zone
      end

      # @return [Hash{Symbol => Object}] extracted article attributes
      def call # rubocop:disable Metrics/MethodLength
        title = extract_title
        lines = leftover_lines
        {
          title:,
          url: extract_url,
          image: extract_image,
          description: ArticleRules::Description.from_lines(lines, title:),
          id: generate_id,
          published_at: extract_published_at(lines),
          enclosures: extract_enclosures,
          categories: extract_categories
        }
      end

      private

      attr_reader :article_tag, :base_url, :selected_anchor, :time_zone

      def extract_url
        @extract_url ||= begin
          href = selected_anchor&.[]('href').to_s

          if href.empty?
            anchorless_url_fallback
          else
            Url.from_relative(href.split('#').first.strip, base_url)
          end
        end
      end

      def anchorless_url_fallback
        return unless @fallback_anchorless

        id = generate_id
        Url.from_relative("##{id}", base_url) if id
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      def extract_title
        source = heading || selected_anchor
        title_text = source ? Navigator.extract_visible_text(source) : fallback_anchorless_title
        return unless title_text

        kicker = kicker_node ? Navigator.extract_visible_text(kicker_node).to_s.strip : nil
        kicker && !kicker.empty? && !title_text.include?(kicker) ? "#{kicker}: #{title_text}" : title_text
      end
      # rubocop:enable Metrics/CyclomaticComplexity

      def fallback_anchorless_title
        return unless @fallback_anchorless && selected_anchor.nil?

        text_node = article_tag.xpath('.//text()').find { |t| !t.text.strip.empty? }
        text_node&.text&.strip
      end

      def heading
        @heading ||= HeadingExtractor.call(
          article_tag,
          fallback_anchorless: @fallback_anchorless,
          selected_anchor:
        )
      end

      def kicker_node
        @kicker_node ||= begin
          selector = '[data-tb-kicker], [class*="kicker"], [class*="eyebrow"], ' \
                     '[class*="pre-title"], [class*="pretitle"], [class*="overline"]'
          node = article_tag.at_css(selector)
          node && heading && (node == heading || Navigator.descendant_of?(node, heading)) ? nil : node
        end
      end

      def leftover_lines
        @leftover_lines ||= ArticleRules::Description.lines_from(
          Navigator.extract_visible_text(article_tag, exclude_nodes: leftover_exclude_nodes)
        )
      end

      def leftover_exclude_nodes
        [heading, selected_anchor, kicker_node, *time_nodes].compact
      end

      def time_nodes
        return [] unless article_tag.respond_to?(:css)

        article_tag.css('time')
      end

      def generate_id
        @generate_id ||= IdGenerator.call(
          article_tag,
          heading:,
          url: (selected_anchor ? extract_url : nil),
          selected_anchor:,
          fallback_anchorless: @fallback_anchorless
        )
      end

      def extract_image = ImageExtractor.call(article_tag, base_url:)

      def extract_published_at(lines) = DateExtractor.call(article_tag, leftover_lines: lines, time_zone:)

      def extract_enclosures = EnclosureExtractor.call(article_tag, base_url)
      def extract_categories = CategoryExtractor.call(article_tag)
    end
  end
end
