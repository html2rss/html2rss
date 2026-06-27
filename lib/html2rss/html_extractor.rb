# frozen_string_literal: true

require 'zlib'

module Html2rss
  ##
  # HtmlExtractor is responsible for extracting details (headline, url, images, etc.)
  # from an article_tag.
  class HtmlExtractor # rubocop:disable Metrics/ClassLength
    # Tags ignored when extracting visible text content from article containers.
    INVISIBLE_CONTENT_TAGS = %w[svg script noscript style template].to_set.freeze
    # Heading tags used to prioritize title extraction.
    HEADING_TAGS = %w[h1 h2 h3 h4 h5 h6].freeze
    # HTML block elements that trigger line breaks or special formatting.
    BLOCK_TAGS = %w[p div li ul ol h1 h2 h3 h4 h5 h6 tr br].to_set.freeze
    # Selector used to derive non-headline description nodes.
    NON_HEADLINE_SELECTOR = (HEADING_TAGS.map { |tag| ":not(#{tag})" } + INVISIBLE_CONTENT_TAGS.to_a).freeze
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
      #
      # @param tag [Nokogiri::XML::Node] the node from which to extract visible text
      # @param separator [String] separator used to join text fragments (default is a space)
      # @param exclude_nodes [Array<Nokogiri::XML::Node>, nil] nodes to exclude from extraction
      # @return [String, nil] the concatenated visible text, or nil if none is found
      def extract_visible_text(tag, separator: ' ', exclude_nodes: nil)
        return tag.text.gsub(/\s+/, ' ').strip if tag.respond_to?(:text?) && tag.text?

        parts = []
        last_was_block = false

        tag.children.each do |child|
          next if exclude_nodes && exclude_nodes.include?(child)
          next unless visible_child?(child)

          child_text = if child.children.empty?
                         child.text.to_s.gsub(/\s+/, ' ').strip
                       else
                         extract_visible_text(child, separator:, exclude_nodes:).to_s.strip
                       end
          next if child_text.empty?

          child_text = "- #{child_text}" if child.name == 'li'

          is_block = BLOCK_TAGS.include?(child.name)
          if is_block || last_was_block
            parts << (separator == ' ' ? "\n" : separator) unless parts.empty?
          elsif !parts.empty?
            parts << ' '
          end

          parts << child_text
          last_was_block = is_block
        end

        parts.join.squeeze(' ').gsub(/\s*(\n|<br>)\s*/, '\1').strip unless parts.empty?
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

      def visible_child?(node)
        !INVISIBLE_CONTENT_TAGS.include?(node.name) &&
          !(node.name == 'a' && node['href']&.start_with?('#'))
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
          if @fallback_anchorless
            item_id = generate_id
            Url.from_relative("##{item_id}", base_url) if item_id
          end
        else
          Url.from_relative(href.split('#').first.strip, base_url)
        end
      end
    end

    def extract_title
      title_source = heading || selected_anchor
      if title_source
        self.class.extract_visible_text(title_source)
      elsif @fallback_anchorless && selected_anchor.nil?
        text_node = article_tag.xpath('.//text()').find { |t| !t.text.strip.empty? }
        text_node&.text&.strip
      end
    end

    def heading
      @heading ||= begin
        tags = article_tag.css(HEADING_TAGS.join(','))
        if tags.any?
          select_best_heading(tags)
        elsif @fallback_anchorless && selected_anchor.nil?
          fallback_tags = article_tag.css('strong, b, [class*="title"], [class*="font-bold"], [class*="font-semibold"]')
          fallback_tags.find { |t| !self.class.extract_visible_text(t).to_s.strip.empty? }
        end
      end
    end

    def select_best_heading(tags)
      min_tag_name = tags.map(&:name).min
      best_tag = nil
      max_size = -1

      tags.each do |tag|
        next if tag.name != min_tag_name

        size = self.class.extract_visible_text(tag)&.size.to_i
        (best_tag = tag) && (max_size = size) if size > max_size
      end

      best_tag
    end

    def extract_description
      exclude = [heading, selected_anchor].compact.to_set
      description = self.class.extract_visible_text(article_tag, exclude_nodes: exclude)
      return nil if description.nil? || description.strip.empty?

      description.strip
    end

    def generate_id
      id_from_dom = [
        article_tag['id'],
        article_tag.at_css('[id]')&.attr('id')
      ]
      id_from_dom += [extract_url&.path, extract_url&.query] if selected_anchor
      id_from_dom = id_from_dom.compact.reject(&:empty?).first

      return id_from_dom if id_from_dom

      heading_node = heading
      heading_text = heading_node ? self.class.extract_visible_text(heading_node) : nil

      if @fallback_anchorless && (heading_text.nil? || heading_text.strip.empty?)
        text_node = article_tag.xpath('.//text()').find { |t| !t.text.strip.empty? }
        heading_text = text_node&.text&.strip
      end

      if heading_text && !heading_text.strip.empty?
        slug = heading_text.downcase.gsub(/[^a-z0-9]+/, '-')
        slug = slug[1..-1] if slug.start_with?('-')
        slug = slug[0..-2] if slug.end_with?('-')
        slug unless slug.empty?
      elsif @fallback_anchorless
        text = self.class.extract_visible_text(article_tag).to_s.strip
        Zlib.crc32(text).to_s(36) unless text.empty?
      end
    end

    def extract_image = ImageExtractor.call(article_tag, base_url:)
    def extract_published_at = DateExtractor.call(article_tag)
    def extract_enclosures = EnclosureExtractor.call(article_tag, base_url)
    def extract_categories = CategoryExtractor.call(article_tag)
  end
end
