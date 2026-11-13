# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  class RequestService
    ##
    # To be used by strategies to provide their response.
    class Response # rubocop:disable Metrics/ClassLength -- transport + capture + cache fields stay co-located
      # Default when a strategy does not attach transport telemetry.
      EMPTY_TRANSPORT_META = {}.freeze
      # Default when a strategy does not capture sub-resource responses.
      EMPTY_CAPTURED_RESPONSES = [].freeze
      # Default when a strategy returns no cookies.
      EMPTY_COOKIES = {}.freeze

      # Bodies that look like HTML even when Content-Type is missing, empty, or wrong.
      HTML_BODY_SNIFF = /\A\s*(?:<!DOCTYPE\s+html|<html)/i
      # Content-Type markers for RSS/Atom/RDF syndication responses.
      FEED_CT_MARKERS = %w[rss+xml atom+xml rdf+xml rss atom].freeze
      # Body sniff for unlabeled syndication (first 800 bytes, downcased).
      FEED_BODY_MARKERS = ['<rss', '<feed xmlns', '<feed ', '<rdf:rdf'].freeze
      # Charset from Content-Type or a leading <meta charset>.
      CHARSET_PARAMETER = /charset\s*=\s*["']?([\w.:-]+)/i
      # Bytes scanned for a meta charset hint (HTML spec looks at the first 1024).
      META_CHARSET_BYTES = 2048
      # The element that sets the document base URL: the first +<base>+ with an +href+ in tree order, unless the
      # parser leaves it inert (inside +template+, +noscript+, +iframe+, +textarea+ or +title+) or it is not an
      # HTML +base+ (inside +svg+).
      BASE_ELEMENT = '//base[@href][not(ancestor::template or ancestor::noscript or ancestor::iframe or ' \
                     'ancestor::textarea or ancestor::title or ancestor::svg)]'
      private_constant :BASE_ELEMENT, :CHARSET_PARAMETER, :META_CHARSET_BYTES, :FEED_CT_MARKERS, :FEED_BODY_MARKERS

      ##
      # @param body [String] the body of the response
      # @param url [Html2rss::Url] the final request URL
      # @param headers [Hash] the headers of the response
      # @param status [Integer, nil] the HTTP status code when available
      # @param transport_meta [Hash] allowlisted upstream telemetry (frozen when present)
      # @param captured_responses [Array<Hash>] JSON XHR/fetch bodies captured during browser scrapes
      # @param cookies [Hash{String => String}] cookies earned during the scrape (session credentials; never log)
      # @param cache_age [Integer, nil] seconds since fetch when served from {ResponseCache}; nil when fetched live
      # rubocop:disable-next Metrics/ParameterLists -- transport + capture fields stay co-located
      def initialize(body:, url:, headers: {}, status: nil, transport_meta: EMPTY_TRANSPORT_META,
                     captured_responses: EMPTY_CAPTURED_RESPONSES, cookies: EMPTY_COOKIES, cache_age: nil)
        @body = body
        @cache_age = cache_age

        @headers = (headers || {}).transform_keys(&:to_s)
        @status = status
        @url = url
        @transport_meta = freeze_or(transport_meta, EMPTY_TRANSPORT_META)
        @cookies = freeze_or(cookies, EMPTY_COOKIES)
        @captured_responses = freeze_or(captured_responses, EMPTY_CAPTURED_RESPONSES)
      end

      # @return [String] the raw body of the response
      attr_reader :body

      # @return [Hash{String => Object}] the headers of the response
      attr_reader :headers

      # @return [Integer, nil] the HTTP status code when known
      attr_reader :status

      # @return [Html2rss::Url] the URL of the response
      attr_reader :url

      ##
      # The document base URL (WHATWG) that relative references in the body resolve against: the first
      # +<base href>+ of an HTML body in tree order (one inside +template+, +noscript+, +iframe+, +textarea+,
      # +title+ or +svg+ does not count) resolved against {#url}, when that is http(s); otherwise {#url}
      # (no +<base>+, an empty +href+, a +javascript:+ or +data:+ one, or a non-HTML body). Only {Selectors} reads
      # it, to resolve item links and enclosures; auto-source, pagination, discovery and every request keep {#url}.
      #
      # @return [Html2rss::Url] the URL a selector config's relative references resolve against
      def base_url
        @base_url ||= document_base_url
      end

      # @return [Hash] allowlisted upstream transport telemetry
      attr_reader :transport_meta

      # @return [Array<Hash>] captured JSON XHR/fetch responses (empty when unsupported)
      attr_reader :captured_responses

      # @return [Hash{String => String}] cookies earned during the scrape (empty when unsupported)
      attr_reader :cookies

      # @return [Integer, nil] seconds since fetch when served from {ResponseCache}; nil when fetched live
      attr_reader :cache_age

      # @param cache_age [Integer, nil] cache age of the copy (defaults to this response's)
      # @return [Response] an independent copy that shares no parsed document with this one
      def replica(cache_age: @cache_age)
        self.class.new(body: body.dup, url:, headers:, status:, transport_meta:, captured_responses:, cookies:,
                       cache_age:)
      end

      # @return [String] normalized content type header value
      def content_type = header('content-type').to_s

      # @return [Boolean] whether the media type is JSON (`*/json` or `*+json`)
      def json_response?
        media_type = content_type.split(';', 2).first.to_s.strip.downcase
        media_type.end_with?('/json', '+json')
      end

      # @return [Boolean] whether response content is HTML (header or sniffed body, never JSON)
      def html_response?
        content_type.include?('text/html') || (!json_response? && !feed_response? && html_looking_body?)
      end

      # @return [Boolean] whether response content is RSS/Atom/RDF (header or sniffed body)
      def feed_response?
        return @feed_response if defined?(@feed_response)

        @feed_response = feed_content_type? || (!json_response? && !html_looking_body? && feed_looking_body?)
      end

      ##
      # @return [Nokogiri::HTML::Document, Hash] the parsed body of the response, frozen object
      # @raise [UnsupportedResponseContentType] if the content type is not supported
      def parsed_body
        @parsed_body ||= if html_response?
                           parse_html_document
                         elsif json_response?
                           JSON.parse(body, symbolize_names: true).freeze
                         else
                           raise UnsupportedResponseContentType, "Unsupported content type: #{content_type}"
                         end
      end

      private

      # @return [Html2rss::Url] the first usable +<base href>+ resolved against {#url}, else {#url}
      def document_base_url
        href = parsed_body.at_xpath(BASE_ELEMENT)&.[]('href') if html_response?
        Url.resolve_web(href, url) || url
      end

      def freeze_or(value, default) = value.nil? || value.empty? ? default : value.freeze

      # @param name [String] canonical header name
      # @return [Object, nil] header value when present
      def header(name)
        headers.fetch(name) do
          headers.find { |key, _value| key.casecmp?(name) }&.last
        end
      end

      def parse_html_document
        Nokogiri::HTML(decoded_html_body).tap do |doc|
          doc.xpath('//comment()').each(&:remove)
        end.freeze
      end

      def decoded_html_body
        bytes = body.to_s.b
        transcode_html(bytes, header_charset || meta_charset(bytes))
      end

      def transcode_html(bytes, charset)
        encoding = html_encoding_for(charset)
        return utf8_scrub(bytes) unless encoding

        bytes.dup.force_encoding(encoding).encode(Encoding::UTF_8)
      rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
        utf8_scrub(bytes)
      end

      def html_encoding_for(charset)
        return if charset.nil? || utf8_charset?(charset)

        Encoding.find(charset)
      rescue ArgumentError
        nil
      end

      def utf8_charset?(charset) = charset.to_s.downcase.gsub(/[\s_-]/, '') == 'utf8'

      def utf8_scrub(bytes) = bytes.dup.force_encoding(Encoding::UTF_8).scrub

      def header_charset
        content_type[CHARSET_PARAMETER, 1]
      end

      def meta_charset(bytes)
        bytes.byteslice(0, META_CHARSET_BYTES).to_s[CHARSET_PARAMETER, 1]
      end

      def html_looking_body?
        body.to_s.b.match?(HTML_BODY_SNIFF)
      end

      def feed_content_type?
        ct = content_type.downcase
        return false if ct.include?('html') || ct.include?('json')

        # Substring match against Content-Type (not Array#intersect? on a String).
        FEED_CT_MARKERS.any? { |marker| ct.include?(marker) }
      end

      def feed_looking_body?
        snippet = body.to_s.b[0, 800].downcase
        FEED_BODY_MARKERS.any? { |marker| snippet.include?(marker) }
      end
    end
  end
end
