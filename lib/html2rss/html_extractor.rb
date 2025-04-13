# frozen_string_literal: true

module Html2rss
  ##
  # HtmlExtractor is responsible for extracting
  # details (headline, url, images, etc.)
  # from an article_tag.
  class HtmlExtractor
    INVISIBLE_CONTENT_TAGS = %w[svg script noscript style template].to_set.freeze
    HEADING_TAGS = %w[h1 h2 h3 h4 h5 h6].freeze
    NON_HEADLINE_SELECTOR = (HEADING_TAGS.map { |s| ":not(#{s})" } + INVISIBLE_CONTENT_TAGS.to_a).freeze

    MAIN_ANCHOR_SELECTOR = begin
      buf = +'a[href]:not([href=""])'
      %w[# javascript: mailto: tel: file:// sms: data:].each { |prefix| buf << %[:not([href^="#{prefix}"])] }
      buf.freeze
    end

    ##
    # Extracts visible text from a given tag and its children.
    #
    # @param tag [Nokogiri::XML::Node] the tag from which to extract visible text
    # @param separator [String] optional separator used to join visible text (default is a space)
    # @return [String, nil] the sanitized visible text or nil if no visible text is found
    def self.extract_visible_text(tag, separator: ' ')
      return tag.text.strip if tag.children.empty?

      visible_text = tag.children.filter_map do |child|
        next if INVISIBLE_CONTENT_TAGS.include?(child.name)

        extract_visible_text(child)
      end.join(separator)

      sanitized_visible_text = visible_text.gsub(/\s+/, ' ').strip
      sanitized_visible_text.empty? ? nil : sanitized_visible_text
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
        enclosure: extract_enclosure
      }
    end

    private

    attr_reader :article_tag, :base_url

    def extract_url
      @extract_url ||= begin
        href = find_main_anchor&.[]('href').to_s

        Utils.build_absolute_url_from_relative(href.split('#').first.strip, base_url) unless href.empty?
      end
    end

    ##
    # Searches for the closest parent anchor which is not in the linking to excluded_hrefs.
    def find_main_anchor
      HtmlNavigator.find_closest_selector_upwards(article_tag, MAIN_ANCHOR_SELECTOR)
    end

    def extract_title
      return unless heading && (heading.children.empty? || heading.text)

      self.class.extract_visible_text(heading)
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
    def extract_enclosure = EnclosureExtractor.call(article_tag, base_url).first
  end
end
