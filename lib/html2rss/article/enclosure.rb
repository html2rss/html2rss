# frozen_string_literal: true

require 'mime/types'

module Html2rss
  class Article
    ##
    # Represents an enclosure attached to an article (RSS / JSON Feed media).
    class Enclosure
      ##
      # Guesses the content type based on the file extension of the URL.
      #
      # @param url [Html2rss::Url]
      # @param default [String] default content type
      # @return [String] guessed content type, or default
      def self.guess_content_type_from_url(url, default: 'application/octet-stream')
        return default unless url

        path = url.path
        ext = File.extname(path)
        ext = ext[1..] if ext.start_with?('.')

        content_type = MIME::Types.type_for(ext)
        content_type.first&.to_s || 'application/octet-stream'
      end

      # @param url [Html2rss::Url] absolute enclosure URL
      # @param type [String, nil] optional enclosure MIME type
      # @param bytes_length [Integer] enclosure length in bytes
      def initialize(url:, type: nil, bytes_length: 0)
        raise ArgumentError, 'An Enclosure requires an absolute URL' if !url || !url.absolute?

        @url = url
        @type = type
        @bytes_length = bytes_length
      end

      # @return [String] explicit MIME type or one inferred from URL extension
      def type = @type || self.class.guess_content_type_from_url(url)

      # @return [Integer] enclosure length in bytes
      attr_reader :bytes_length

      # @return [Html2rss::Url] absolute enclosure URL
      attr_reader :url
    end
  end
end
