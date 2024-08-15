# frozen_string_literal: true

require 'zlib'
require 'sanitize'

module Html2rss
  class AutoSource
    ##
    # Article is a simple data object representing an article extracted from a page.
    # It is enumerable and responds to all keys specified in PROVIDED_KEYS.
    class Article
      include Enumerable

      PROVIDED_KEYS = %i[id title description url image guid published_at generated_by].freeze

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
        # TODO: reuse Postprocessor Sanitize
        @description ||= Sanitize.fragment(@to_h[:description])
      end

      # @return [Addressable::URI, nil]
      def url
        @url ||= Html2rss::Utils.sanitize_url(@to_h[:url])
      end

      # @return [Addressable::URI, nil]
      def image
        @image ||= Html2rss::Utils.sanitize_url(@to_h[:image])
      end

      # Generates a unique identifier based on the URL and ID using CRC32.
      # @return [String]
      def guid
        @guid ||= Zlib.crc32([url, id].join('#!/')).to_s(36).encode('utf-8')
      end

      # Parses and returns the published_at time.
      # @return [Time, nil]
      def published_at
        return if (string = @to_h[:published_at].to_s).strip.empty?

        @published_at ||= Time.parse(string)
      rescue ArgumentError
        nil
      end

      def generated_by
        @to_h[:generated_by]
      end
    end
  end
end
