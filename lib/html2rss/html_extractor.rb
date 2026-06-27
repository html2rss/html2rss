# frozen_string_literal: true

module Html2rss
  ##
  # HtmlExtractor is responsible for extracting details (headline, url, images, etc.)
  # from an article_tag.
  # rubocop:disable Metrics/ClassLength
  class HtmlExtractor
    # Heading tags used to prioritize title extraction.
    HEADING_TAGS = %w[h1 h2 h3 h4 h5 h6].freeze

    # Element tags that indicate ignored DOM chrome when found in a container path.
    IGNORED_CONTAINER_TAGS = %w[nav footer header svg script style].to_set.freeze

    # Anchor selector used to identify the canonical article link element.
    MAIN_ANCHOR_SELECTOR = begin
      buf = +'a[href]:not([href=""])'
      %w[# javascript: mailto: tel: file:// sms: data:].each do |prefix|
        buf << %[:not([href^="#{prefix}"])]
      end
      buf.freeze
    end

    class << self
      ##
      # Extracts visible text from a given node and its children.
      # Delegates to TextExtractor.
      #
      # @param tag [Nokogiri::XML::Node] the node from which to extract visible text
      # @param separator [String] separator used to join text fragments (default is a space)
      # @param exclude_nodes [Array<Nokogiri::XML::Node>, nil] nodes to exclude from extraction
      # @return [String, nil] the concatenated visible text, or nil if none is found
      def extract_visible_text(tag, separator: ' ', exclude_nodes: nil)
        TextExtractor.call(tag, separator:, exclude_nodes:)
      end

      ##
      # @param article_tag [Nokogiri::XML::Node] article-like container to search within
      # @return [Nokogiri::XML::Node, nil] first eligible descendant anchor
      def main_anchor_for(article_tag)
        return article_tag if article_tag.name == 'a' && article_tag.matches?(MAIN_ANCHOR_SELECTOR)

        article_tag.at_css(MAIN_ANCHOR_SELECTOR)
      end

      ##
      # @param node [Nokogiri::XML::Node]
      # @param cache [Hash, nil] identity cache used to store results (must use compare_by_identity)
      # @return [Boolean] true when the node belongs to ignored DOM chrome
      def ignored_container_path?(node, cache = nil)
        return cache[node] if cache&.key?(node)

        res = walk_ignored_container_path?(node)
        cache[node] = res if cache
        res
      end

      private

      def walk_ignored_container_path?(node)
        curr = node
        while curr.respond_to?(:parent)
          return true if IGNORED_CONTAINER_TAGS.include?(curr.name)

          curr = curr.parent
        end
        false
      end
    end

    ##
    # @param article_tag [Nokogiri::XML::Node] article-like container to extract from
    # @param base_url [String, Html2rss::Url] base url used to resolve relative links
    # @param selected_anchor [Nokogiri::XML::Node, nil] explicit primary anchor for the container
    # @param fallback_anchorless [Boolean] whether to fall back to anchorless extraction
    def initialize(article_tag, base_url:, selected_anchor:, fallback_anchorless: false)
      raise ArgumentError, 'article_tag is required' unless article_tag

      @article_tag = article_tag
      @base_url = base_url
      @selected_anchor = selected_anchor
      @fallback_anchorless = fallback_anchorless
    end

    # @return [Hash{Symbol => Object}] extracted article attributes
    def call
      {
        title: extract_title,
        url: extract_url,
        image: extract_image,
        description: extract_description,
        id: generate_id,
        published_at: extract_published_at,
        enclosures: extract_enclosures,
        categories: extract_categories
      }
    end

    private

    attr_reader :article_tag, :base_url, :selected_anchor

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

    def extract_title
      title_source = heading || selected_anchor
      if title_source
        self.class.extract_visible_text(title_source)
      else
        fallback_anchorless_title
      end
    end

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

    def extract_description
      exclude = [heading, selected_anchor].compact.to_set
      description = self.class.extract_visible_text(article_tag, exclude_nodes: exclude)
      return if description.nil?

      desc = description.strip
      desc.empty? ? nil : desc
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
    def extract_published_at = DateExtractor.call(article_tag)
    def extract_enclosures = EnclosureExtractor.call(article_tag, base_url)
    def extract_categories = CategoryExtractor.call(article_tag)
  end
  # rubocop:enable Metrics/ClassLength
end
