# frozen_string_literal: true

require 'brotli'
require 'stringio'
require 'zlib'

module Html2rss
  class RequestService
    # Decodes gzip/brotli bodies when Content-Encoding is missing or the type is octet-stream.
    class CompressedBody
      # Gzip stream magic (RFC 1952).
      GZIP_MAGIC = "\x1F\x8B".b.freeze
      # HTML prefix for unlabeled brotli trial decode. Same object as {Response::HTML_BODY_SNIFF}.
      HTML_BODY_SNIFF = Response::HTML_BODY_SNIFF

      # @param body [String, nil] raw response body
      # @param headers [Hash] response headers (Content-Encoding / Content-Type)
      # @return [String, nil] decoded body when compressed; otherwise the original body
      def self.decode(body, headers: {})
        return body if body.nil? || body.empty?

        raw = body.to_s.b
        new(raw, headers).decoded_body || body
      end

      # @param raw [String] binary response body
      # @param headers [Hash] response headers (Content-Encoding / Content-Type)
      def initialize(raw, headers)
        @raw = raw
        @headers = headers
      end
      private_class_method :new

      # @return [String, nil] inflated body, or nil when the bytes are not a recognized stream
      def decoded_body
        decode_labeled || decode_unlabeled
      end

      private

      def decode_labeled
        encodings = content_encodings
        return if encodings.empty?

        encodings.reverse.reduce(@raw) { |buffer, encoding| inflate(buffer, encoding) || buffer }
      end

      def decode_unlabeled
        return uncompress_gzip(@raw) if @raw.start_with?(GZIP_MAGIC)
        return unless octet_stream?

        try_brotli(@raw)
      end

      def inflate(raw, encoding)
        case encoding
        when 'gzip'
          return raw unless raw.start_with?(GZIP_MAGIC)

          uncompress_gzip(raw)
        when 'br' then try_brotli(raw, require_html: false)
        when 'deflate' then inflate_deflate(raw)
        end
      rescue Zlib::Error, Brotli::Error, ArgumentError
        nil
      end

      def inflate_deflate(raw)
        inflater = nil
        Zlib::Inflate.inflate(raw)
      rescue Zlib::DataError
        inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
        inflater.inflate(raw)
      ensure
        inflater&.close
      end

      def uncompress_gzip(raw)
        Zlib::GzipReader.wrap(StringIO.new(raw), &:read).b
      rescue Zlib::Error
        nil
      end

      def try_brotli(raw, require_html: true)
        inflated = Brotli.inflate(raw)
        return inflated unless require_html
        return inflated if inflated.b.match?(HTML_BODY_SNIFF)

        nil
      rescue Brotli::Error, ArgumentError
        nil
      end

      def content_encodings
        header('content-encoding')
          .to_s
          .split(',')
          .filter_map { |val| (s = val.strip.downcase).empty? ? nil : s }
      end

      def octet_stream?
        header('content-type').to_s.downcase.include?('application/octet-stream')
      end

      def header(name)
        @headers.fetch(name) do
          @headers.find { |key, _value| key.to_s.casecmp?(name) }&.last
        end
      end
    end
  end
end
