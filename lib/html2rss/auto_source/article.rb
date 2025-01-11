# frozen_string_literal: true

require 'zlib'
require 'sanitize'
require 'nokogiri'

module Html2rss
  class AutoSource
    ##
    # Article is a simple data object representing an article extracted from a page.
    # It is enumerable and responds to all keys specified in PROVIDED_KEYS.
    class Article
      include Enumerable
      include Comparable

      PROVIDED_KEYS = %i[id title description url image guid published_at scraper].freeze

      ##
      # Removes the specified pattern from the beginning of the text
      # within a given range if the pattern occurs before the range's end.
      #
      # @param text [String]
      # @param pattern [String]
      # @param end_of_range [Integer] - Optional, defaults to half the size of the text
      # @return [String]
      def self.remove_pattern_from_start(text, pattern, end_of_range: (text.size * 0.5).to_i)
        return text unless text.is_a?(String) && pattern.is_a?(String)

        index = text.index(pattern)
        return text if index.nil? || index >= end_of_range

        text.gsub(/^(.{0,#{end_of_range}})#{Regexp.escape(pattern)}/, '\1')
      end

      ##
      # Checks if the text contains HTML tags.
      # @param text [String]
      # @return [Boolean]
      def self.contains_html?(text)
        Nokogiri::HTML.fragment(text).children.any?(&:element?)
      end

      # @param options [Hash<Symbol, String>]
      def initialize(**options)
        @to_h = {}
        options.each_pair { |key, value| @to_h[key] = value.freeze if value }
        @to_h.freeze

        return unless (unknown_keys = options.keys - PROVIDED_KEYS).any?

        Log.warn "Article: unknown keys found: #{unknown_keys.join(', ')}"
      end

      # Checks if the article is valid based on the presence of URL, ID, and either title or description.
      # @return [Boolean] True if the article is valid, otherwise false.
      def valid?
        !url.to_s.empty? && (!title.to_s.empty? || !description.to_s.empty?) && !id.to_s.empty?
      end

      # @yield [key, value]
      # @return [Enumerator] if no block is given
      def each
        return enum_for(:each) unless block_given?

        PROVIDED_KEYS.each { |key| yield(key, public_send(key)) }
      end

      def id
        @to_h[:id]
      end

      def title
        @to_h[:title]
      end

      def description
        return @description if defined?(@description)

        return if (description = @to_h[:description]).to_s.empty?

        @description = self.class.remove_pattern_from_start(description, title) if title

        if self.class.contains_html?(@description) && url
          @description = Html2rss::AttributePostProcessors::SanitizeHtml.get(description, url)
        else
          @description
        end
      end

      # @return [Addressable::URI, nil]
      def url
        @url ||= Html2rss::Utils.sanitize_url(@to_h[:url])
      end

      # @return [Addressable::URI, nil]
      def image
        @image ||= Html2rss::Utils.sanitize_url(@to_h[:image])
      end

      # @return [String]
      def author = @to_h[:author]

      # Generates a unique identifier based on the URL and ID using CRC32.
      # @return [String]
      def guid
        @guid ||= begin
          guid = @to_h[:guid].to_a.map { |o| o.to_s.strip }.reject(&:empty?).join('|')
          guid = [url, id].join('#!/') if guid.empty?

          Zlib.crc32(guid).to_s(36).encode('utf-8')
        end
      end

      # @return [Html2rss::Enclosure, nil]
      def enclosure
        if @to_h[:enclosure]
          @to_h[:enclosure]
        elsif image
          Html2rss::Enclosure.new(url: image)
        end
      end

      def categories = @to_h[:categories]

      # Parses and returns the published_at time.
      # @return [DateTime, nil]
      def published_at
        return if (string = @to_h[:published_at].to_s.strip).empty?

        @published_at ||= DateTime.parse(string)
      rescue ArgumentError
        nil
      end

      def scraper
        @to_h[:scraper]
      end

      def <=>(other)
        return nil unless other.is_a?(Article)

        0 if other.all? { |key, value| value == public_send(key) ? public_send(key) <=> value : false }
      end
    end
  end
end
