# frozen_string_literal: true

require 'mime/types'

module Html2rss
  class Article
    ##
    # Represents an enclosure attached to an article (RSS / JSON Feed media).
    #
    # The one owner of media-file facts: URL, MIME type, byte length and playback duration,
    # the media-kind predicates feed builders choose by, and the parsers that turn
    # publisher-declared size and duration strings into those facts.
    class Enclosure
      # A byte size: a number with an optional unit (+12345+, +850 KB+, +12.3 MB+, +1.5GiB+).
      SIZE = /\A\s*(\d+(?:\.\d+)?)\s*([kmgt]i?b|b|bytes?)?\s*\z/i
      # Bytes per size unit; SI prefixes count in thousands, binary (+KiB+) in 1024s.
      SIZE_UNITS = {
        'b' => 1, 'byte' => 1, 'bytes' => 1,
        'kb' => 1000, 'mb' => 1000**2, 'gb' => 1000**3, 'tb' => 1000**4,
        'kib' => 1024, 'mib' => 1024**2, 'gib' => 1024**3, 'tib' => 1024**4
      }.freeze
      # An ISO 8601 duration of days and time parts (+PT1H2M3S+, +PT45M+, +P1DT2H+).
      DURATION = /\AP(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?)?\z/
      # Types of web pages (embed players, article pages), never a media file.
      PAGE_TYPES = %w[application/xhtml+xml].freeze

      class << self
        ##
        # Guesses the content type based on the file extension of the URL.
        #
        # @param url [Html2rss::Url]
        # @param default [String] default content type
        # @return [String] guessed content type, or default
        def guess_content_type_from_url(url, default: 'application/octet-stream')
          return default unless url

          found = MIME::Types.type_for(url.path).first
          found&.content_type || default
        end

        ##
        # Parses a declared file size (Schema.org +contentSize+ and alike) into bytes.
        #
        # @param value [String, Integer, nil] e.g. +"12.3 MB"+, +"850 KB"+, +"12345"+
        # @return [Integer, nil] positive byte count, or nil when unparseable
        def parse_size(value)
          return unless (match = SIZE.match(value.to_s))

          bytes = (Float(match[1]) * SIZE_UNITS.fetch(match[2].to_s.downcase, 1)).round
          bytes if bytes.positive?
        end

        ##
        # Parses an ISO 8601 duration (Schema.org +duration+) into seconds.
        #
        # @param value [String, nil] e.g. +"PT1H2M3S"+, +"PT45M"+
        # @return [Integer, nil] positive seconds, or nil when unparseable
        def parse_duration(value)
          return unless (match = DURATION.match(value.to_s.strip.upcase))

          days, hours, minutes, seconds = match.captures.map(&:to_f)
          total = ((days * 86_400) + (hours * 3600) + (minutes * 60) + seconds).round
          total if total.positive?
        end
      end

      # @param url [Html2rss::Url] absolute enclosure URL
      # @param type [String, nil] optional enclosure MIME type
      # @param bytes_length [Integer, nil] enclosure length in bytes; nil when unknown
      # @param duration [Integer, nil] playback length in seconds; nil (or not positive) when unknown
      def initialize(url:, type: nil, bytes_length: nil, duration: nil)
        raise ArgumentError, 'An Enclosure requires an absolute URL' if !url || !url.absolute?

        @url = url
        @type = type
        @bytes_length = bytes_length || 0
        @duration = duration if duration.instance_of?(Integer) && duration.positive?
      end

      # @return [String] explicit MIME type or one inferred from URL extension
      def type = @type || self.class.guess_content_type_from_url(url)

      # @return [Integer] enclosure length in bytes; 0 when unknown
      attr_reader :bytes_length

      # @return [Integer, nil] playback length in seconds
      attr_reader :duration

      # @return [Html2rss::Url] absolute enclosure URL
      attr_reader :url

      # @return [Boolean] whether the file is audio or video
      def media? = type.downcase.start_with?('audio/', 'video/')

      # @return [Boolean] whether the file is an image
      def image? = type.downcase.start_with?('image/')

      # @return [Boolean] whether the URL is a web page (+text/*+, XHTML), such as an embed player
      def page?
        mime = type.downcase
        mime.start_with?('text/') || PAGE_TYPES.include?(mime)
      end
    end
  end
end
