# frozen_string_literal: true

require 'mime/types'

module Html2rss
  ##
  # Represents an enclosure for an RSS item.
  class Enclosure
    ##
    # Guesses the content type based on the file extension of the URL.
    #
    # @param url [Addressable::URI]
    # @param default [String] default content type
    # @return [String] guessed content type, or default
    def self.guess_content_type_from_url(url, default: 'application/octet-stream')
      return default unless url

      url = url.path.split('?').first

      content_type = MIME::Types.type_for(File.extname(url).delete('.'))
      content_type.first&.to_s || 'application/octet-stream'
    end

    def initialize(url:, type: nil, bits_length: 0)
      raise ArgumentError, 'An Enclosure requires an absolute URL' if !url || !url.absolute?

      @url = url
      @type = type
      @bits_length = bits_length
    end

    def type = @type || self.class.guess_content_type_from_url(url)

    attr_reader :bits_length, :url
  end
end
