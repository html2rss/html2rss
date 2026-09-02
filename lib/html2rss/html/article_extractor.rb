# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # ArticleExtractor is responsible for extracting details (headline, url, images, etc.)
    # from an article_tag DOM node. DOM chrome helpers live on {Navigator}.
    # rubocop:disable Metrics/ClassLength -- leftover re-extract stays with field extractors
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
        published_at = extract_published_at(lines)
        source, lines, published_at = parent_card_fields(title, lines, published_at)
        {
          title:,
          url: extract_url,
          image: extract_image,
          description: ArticleRules::Description.from_lines(lines, title:),
          id: generate_id,
          published_at:,
          enclosures: extract_enclosures,
          categories: CategoryExtractor.call(source, title:)
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
        leftover_lines_from(article_tag)
      end

      def leftover_lines_from(node)
        ArticleRules::Description.lines_from(
          Navigator.extract_visible_text(node, exclude_nodes: leftover_exclude_nodes_for(node))
        )
      end

      def leftover_exclude_nodes_for(node)
        times = node.respond_to?(:css) ? node.css('time') : []
        [heading, selected_anchor, kicker_node, *times].compact
      end

      def heading_or_anchor_item?
        tag = Probe.tag(article_tag)
        Navigator::HEADING_TAGS.include?(tag) || tag == 'a'
      end

      def heading_or_anchor_miss?(title, lines, published_at)
        CardWalk.miss?(
          heading_or_anchor_item: heading_or_anchor_item?,
          published_at:,
          description: ArticleRules::Description.from_lines(lines, title:)
        )
      end

      def parent_card_fields(title, lines, published_at)
        return article_tag, lines, published_at unless heading_or_anchor_miss?(title, lines, published_at)

        parent = immediate_card_parent
        if !parent || crowded_parent?(parent)
          Log.debug { "parent-walk abort at #{article_tag.parent&.name}" }
          return article_tag, lines, published_at
        end

        new_lines = leftover_lines_from(parent)
        new_date = extract_published_at_from(parent, new_lines)
        [parent, new_lines, new_date || published_at]
      end

      def immediate_card_parent
        parent = article_tag.respond_to?(:parent) ? article_tag.parent : nil
        Navigator.parent_until_condition(parent, method(:usable_walk_parent?))
      end

      def usable_walk_parent?(node)
        Navigator.usable_card_parent?(node) && !thin_heading_wrapper?(node)
      end

      def thin_heading_wrapper?(node)
        CardWalk.thin_wrapper?(
          children: node.element_children,
          item: article_tag,
          descendant_of: ->(item, child) { Navigator.descendant_of?(item, child) }
        )
      end

      def crowded_parent?(node)
        CardWalk.crowded?(
          heading_count: node.css(Navigator::HEADING_TAGS.join(',')).size,
          distinct_main_hrefs: distinct_main_hrefs(node)
        )
      end

      def distinct_main_hrefs(node)
        node.css(Navigator::MAIN_ANCHOR_SELECTOR).map { |anchor| anchor['href'] }.uniq.size
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

      def extract_published_at(lines) = extract_published_at_from(article_tag, lines)

      def extract_published_at_from(node, lines)
        DateExtractor.call(node, leftover_lines: lines, time_zone:)
      end

      def extract_enclosures = EnclosureExtractor.call(article_tag, base_url)
    end
    # rubocop:enable Metrics/ClassLength
  end
end
