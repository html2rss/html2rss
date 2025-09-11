# frozen_string_literal: true

module Html2rss
  ##
  # HtmlExtractor is responsible for extracting details (headline, url, images, etc.)
  # from an article_tag.
  class HtmlExtractor
    INVISIBLE_CONTENT_TAGS = %w[svg script noscript style template].to_set.freeze
    HEADING_TAGS = %w[h1 h2 h3 h4 h5 h6].freeze
    NON_HEADLINE_SELECTOR = (HEADING_TAGS.map { |tag| ":not(#{tag})" } + INVISIBLE_CONTENT_TAGS.to_a).freeze

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
      # @return [String, nil] the concatenated visible text, or nil if none is found
      def extract_visible_text(tag, separator: ' ')
        parts = collect_visible_text_parts(tag)
        format_text_parts(parts, separator)
      end

      private

      def collect_visible_text_parts(tag)
        tag.children.each_with_object([]) do |child, result|
          next unless visible_child?(child)

          raw_text = extract_text_from_child(child)
          next unless raw_text

          text = raw_text.strip
          result << text unless text.empty?
        end
      end

      def extract_text_from_child(child)
        child.children.empty? ? child.text : extract_visible_text(child)
      end

      def format_text_parts(parts, separator)
        return nil if parts.empty?

        parts.join(separator).squeeze(' ').strip
      end

      def visible_child?(node)
        !INVISIBLE_CONTENT_TAGS.include?(node.name) &&
          !(node.name == 'a' && node['href']&.start_with?('#'))
      end
    end

    def initialize(article_tag, base_url:)
      raise ArgumentError, 'article_tag is required' unless article_tag

      @article_tag = article_tag
      @base_url = base_url
    end

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

    attr_reader :article_tag, :base_url

    def extract_url
      @extract_url ||= begin
        href = find_main_anchor&.[]('href').to_s

        Url.from_relative(href.split('#').first.strip, base_url) unless href.empty?
      end
    end

    # Finds the closest ancestor anchor element matching the MAIN_ANCHOR_SELECTOR.
    def find_main_anchor
      HtmlNavigator.find_closest_selector_upwards(article_tag, MAIN_ANCHOR_SELECTOR)
    end

    def extract_title
      self.class.extract_visible_text(heading) if heading
    end

    def heading
      @heading ||= begin
        heading_tags = article_tag.css(HEADING_TAGS.join(',')).group_by(&:name)
        smallest_heading = heading_tags.keys.min
        if smallest_heading
          heading_tags[smallest_heading]&.max_by do |tag|
            self.class.extract_visible_text(tag)&.size.to_i
          end
        end
      end
    end

    def extract_description
      text = self.class.extract_visible_text(article_tag.css(NON_HEADLINE_SELECTOR), separator: '<br>')
      return text if text && !text.empty?

      description = self.class.extract_visible_text(article_tag)
      return nil if description.nil? || description.strip.empty?

      description.strip
    end

    def generate_id
      [
        article_tag['id'],
        article_tag.at_css('[id]')&.attr('id'),
        extract_url&.path,
        extract_url&.query
      ].compact.reject(&:empty?).first
    end

    def extract_image = ImageExtractor.call(article_tag, base_url:)
    def extract_published_at = DateExtractor.call(article_tag)
    def extract_enclosures = EnclosureExtractor.call(article_tag, base_url)
    def extract_categories = CategoryExtractor.call(article_tag)
  end
end
