# frozen_string_literal: true

require 'mime/types'

module Html2rss
  class RssBuilder
    ##
    # Represents an enclosure for an RSS item.
    class Enclosure
      ##
      # Guesses the content type based on the file extension of the URL.
      #
      # @param url [Html2rss::Url]
      # @param default [String] default content type
      # @return [String] guessed content type, or default
      def self.guess_content_type_from_url(url, default: 'application/octet-stream')
        return default unless url

        url = url.path.split('?').first

        content_type = MIME::Types.type_for(File.extname(url).delete('.'))
        content_type.first&.to_s || 'application/octet-stream'
      end

      # @param enclosure [Html2rss::RssBuilder::Enclosure, nil] built enclosure object for the current RSS item
      # @param maker [RSS::Maker::RSS20::ItemsBase::ItemBase] RSS item builder
      # @return [void]
      def self.add(enclosure, maker)
        return unless enclosure

        maker.enclosure.tap do |enclosure_maker|
          enclosure_maker.url = enclosure.url.to_s
          enclosure_maker.type = enclosure.type
          enclosure_maker.length = enclosure.bits_length
        end
      end

      # @param url [Html2rss::Url] absolute enclosure URL
      # @param type [String, nil] optional enclosure MIME type
      # @param bits_length [Integer] enclosure byte length
      def initialize(url:, type: nil, bits_length: 0)
        raise ArgumentError, 'An Enclosure requires an absolute URL' if !url || !url.absolute?

        @url = url
        @type = type
        @bits_length = bits_length
      end

      # @return [String] explicit MIME type or one inferred from URL extension
      def type = @type || self.class.guess_content_type_from_url(url)

      attr_reader :bits_length, :url
    end
  end
end
