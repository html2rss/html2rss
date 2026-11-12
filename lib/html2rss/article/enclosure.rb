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
      # A clock duration (+itunes:duration+, Media RSS): +HH:MM:SS+, +MM:SS+ or plain seconds.
      CLOCK = /\A(?:(?:(\d+):)?(\d+):)?(\d+(?:\.\d+)?)\z/
      # Types of web pages (embed players, article pages), never a media file: HTML, XHTML and the
      # types MIME::Types guesses from server-page script extensions (+.php+, +.asp+, +.aspx+, +.jsp+,
      # +.cgi+, +.cfm+). Other +text/*+ files (+.txt+, +.csv+, +.ics+, +.vtt+) are downloads.
      PAGE_TYPES = %w[
        text/html application/xhtml+xml text/x-php application/x-httpd-php text/asp text/aspdotnet text/x-jsp
        text/x-cgi text/x-coldfusion
      ].freeze
      # Types of stream playlists (HLS, DASH) and Flash players: played through a page or player, never
      # downloaded as a file.
      STREAM_TYPES = %w[
        application/vnd.apple.mpegurl application/x-mpegurl application/dash+xml application/x-shockwave-flash
      ].freeze
      # The type of a URL that declares none and has no known extension.
      UNTYPED = 'application/octet-stream'
      # Playable audio/video types by file extension. MIME::Types lists these extensions under
      # several types and puts a non-playable or codec-level one first (+.mp4+ as +application/mp4+,
      # +.ogg+ as +audio/vorbis+, +.m4v+ without +video/mp4+), so media extensions are looked up here first.
      # HLS playlists (+.m3u8+) are no media file: MIME::Types types them +application/vnd.apple.mpegurl+.
      MEDIA_TYPES = {
        'mp4' => 'video/mp4', 'm4v' => 'video/mp4', 'ogv' => 'video/ogg', 'webm' => 'video/webm',
        'm4a' => 'audio/mp4', 'mp3' => 'audio/mpeg', 'ogg' => 'audio/ogg', 'oga' => 'audio/ogg',
        'opus' => 'audio/opus', 'aac' => 'audio/aac', 'wav' => 'audio/wav', 'flac' => 'audio/flac'
      }.freeze
      # The type of a file an audio or video player proves is media while its URL names no media type
      # (no or an unknown extension, or a server page): the most widely played format of that kind, since
      # an RSS enclosure needs a concrete type and +audio/*+ is none.
      KIND_TYPES = { audio: 'audio/mpeg', video: 'video/mp4' }.freeze

      class << self
        ##
        # Guesses the content type based on the file extension of the URL: a media extension
        # ({MEDIA_TYPES}) gives its audio or video type, any other the first MIME::Types match.
        #
        # @param url [Html2rss::Url]
        # @param default [String] default content type
        # @return [String] guessed content type, or default
        def guess_content_type_from_url(url, default: UNTYPED)
          return default unless url

          path = url.path
          MEDIA_TYPES[File.extname(path).delete_prefix('.').downcase] ||
            MIME::Types.type_for(path).first&.content_type || default
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
        # Parses a declared playback duration into seconds: ISO 8601 (Schema.org +duration+) or a
        # clock (+itunes:duration+, Media RSS +duration+).
        #
        # @param value [String, Integer, nil] e.g. +"PT1H2M3S"+, +"PT45M"+, +"1:02:03"+, +"45:00"+, +"2700"+
        # @return [Integer, nil] positive seconds, or nil when unparseable
        def parse_duration(value)
          return unless (parts = duration_parts(value.to_s.strip.upcase))

          days, hours, minutes, seconds = parts.map(&:to_f)
          total = ((days * 86_400) + (hours * 3600) + (minutes * 60) + seconds).round
          total if total.positive?
        end

        private

        # @return [Array<String, nil>, nil] days, hours, minutes and seconds, or nil when no duration shape matches
        def duration_parts(text)
          DURATION.match(text)&.captures || CLOCK.match(text)&.captures&.unshift(nil)
        end
      end

      # @param url [Html2rss::Url] absolute enclosure URL
      # @param type [String, nil] optional enclosure MIME type
      # @param bytes_length [Integer, nil] enclosure length in bytes; nil when unknown
      # @param duration [Integer, nil] playback length in seconds; nil (or not positive) when unknown
      # @param kind [Symbol, nil] +:audio+ or +:video+ when a player or media object proves the file's kind
      #   ({KIND_TYPES}); nil when unknown
      def initialize(url:, type: nil, bytes_length: nil, duration: nil, kind: nil)
        raise ArgumentError, 'An Enclosure requires an absolute URL' if !url || !url.absolute?

        @url = url
        @type = type
        @bytes_length = bytes_length || 0
        @duration = duration if duration.instance_of?(Integer) && duration.positive?
        @kind_type = kind_type(kind)
      end

      # @return [String] explicit MIME type, else one inferred from the URL extension; a file of a known kind whose
      #   URL names no media type takes that kind's type ({KIND_TYPES}), also when it is declared {UNTYPED}
      def type = (@type unless @kind_type && @type&.casecmp?(UNTYPED)) || guessed_type

      # @return [Integer] enclosure length in bytes; 0 when unknown
      attr_reader :bytes_length

      # @return [Integer, nil] playback length in seconds
      attr_reader :duration

      # @return [Html2rss::Url] absolute enclosure URL
      attr_reader :url

      # @return [Boolean] whether the file is audio
      def audio? = mime.start_with?('audio/')

      # @return [Boolean] whether the file is video
      def video? = mime.start_with?('video/')

      # @return [Boolean] whether the file is audio or video
      def media? = audio? || video?

      # @return [Boolean] whether the file is an image
      def image? = mime.start_with?('image/')

      # @return [Boolean] whether the URL is a web page ({PAGE_TYPES}: HTML, XHTML, a server page), such as an
      #   embed player
      def page? = PAGE_TYPES.include?(mime)

      # @return [Boolean] whether the URL path ends in a file extension (+.pdf+), unlike a watch page (+/watch/42+)
      def file_extension? = !File.extname(url.path).empty?

      # A watch or player page (+/watch/42+) declared as a file: a web page ({#page?}), or an untyped URL
      # ({UNTYPED}: no declared type and no known file extension) with no file extension and no declared
      # byte length. A declared length makes an extensionless URL a file (+/download/42+), since only a
      # file has one.
      #
      # @return [Boolean] whether the URL is a watch or player page rather than a file
      def player_page?
        page? || (mime == UNTYPED && !file_extension? && bytes_length.zero?)
      end

      # A downloadable document or archive (PDF, ZIP): no media file, image, stream playlist or Flash
      # player ({STREAM_TYPES}), and no watch or player page ({#player_page?}).
      #
      # @return [Boolean] whether the URL is a downloadable document or archive
      def document? = !(media? || image? || STREAM_TYPES.include?(mime) || player_page?)

      private

      # @return [String] the lowercase MIME type without parameters (+audio/ogg; codecs=opus+ is +audio/ogg+)
      def mime = type.downcase[/\A[^;\s]*/]

      # @param kind [Symbol, nil]
      # @return [String, nil] the type a file of that kind takes when its URL names none ({KIND_TYPES})
      # @raise [ArgumentError] for a kind other than +:audio+ or +:video+
      def kind_type(kind)
        return unless kind

        KIND_TYPES.fetch(kind) { raise ArgumentError, "Unknown enclosure kind: #{kind.inspect}" }
      end

      # The type guessed from the URL; a file of a known kind whose URL names no media type (untyped, or a
      # server page) takes that kind's type ({KIND_TYPES}) instead.
      #
      # @return [String]
      def guessed_type
        guessed = self.class.guess_content_type_from_url(url)
        return guessed unless @kind_type && (guessed == UNTYPED || PAGE_TYPES.include?(guessed))

        @kind_type
      end
    end
  end
end
