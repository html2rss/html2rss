# frozen_string_literal: true

require 'brotli'
require 'stringio'
require 'zlib'

module Html2rss
  class RequestService
    # Decodes gzip/brotli bodies when Content-Encoding is missing or the type is octet-stream.
    module CompressedBody
      # Gzip stream magic (RFC 1952).
      GZIP_MAGIC = "\x1F\x8B".b.freeze
      HTML_BODY_SNIFF = Response::HTML_BODY_SNIFF

      module_function

      # @param body [String, nil] raw response body
      # @param headers [Hash] response headers (Content-Encoding / Content-Type)
      # @return [String, nil] decoded body when compressed; otherwise the original body
      def decode(body, headers: {})
        return body if body.nil? || body.empty?

        raw = body.to_s.b
        decode_labeled(raw, headers) || decode_unlabeled(raw, headers) || body
      end

      def decode_labeled(raw, headers)
        encodings = content_encodings(headers)
        return if encodings.empty?

        encodings.reverse.reduce(raw) { |buffer, encoding| inflate(buffer, encoding) || buffer }
      end
      module_function :decode_labeled
      private_class_method :decode_labeled

      def decode_unlabeled(raw, headers)
        return uncompress_gzip(raw) if raw.start_with?(GZIP_MAGIC)
        return unless octet_stream?(headers)

        try_brotli(raw)
      end
      module_function :decode_unlabeled
      private_class_method :decode_unlabeled

      def inflate(raw, encoding)
        case encoding
        when 'gzip' then uncompress_gzip(raw)
        when 'deflate' then inflate_deflate(raw)
        when 'br' then try_brotli(raw, require_html: false)
        end
      rescue Zlib::Error, Brotli::Error, ArgumentError
        nil
      end
      module_function :inflate
      private_class_method :inflate

      def uncompress_gzip(raw)
        Zlib::GzipReader.wrap(StringIO.new(raw), encoding: 'ASCII-8BIT', &:read)
      end
      module_function :uncompress_gzip
      private_class_method :uncompress_gzip

      def inflate_deflate(raw)
        inflater = nil
        Zlib::Inflate.inflate(raw)
      rescue Zlib::DataError
        inflater = Zlib::Inflate.new(-Zlib::MAX_WBITS)
        inflater.inflate(raw)
      ensure
        inflater&.close
      end
      module_function :inflate_deflate
      private_class_method :inflate_deflate

      def try_brotli(raw, require_html: true)
        inflated = Brotli.inflate(raw)
        return inflated unless require_html
        return inflated if inflated.b.match?(HTML_BODY_SNIFF)

        nil
      rescue Brotli::Error, ArgumentError
        nil
      end
      module_function :try_brotli
      private_class_method :try_brotli

      def content_encodings(headers)
        header(headers, 'content-encoding').to_s.split(',').map { |value| value.strip.downcase }.reject(&:empty?)
      end
      module_function :content_encodings
      private_class_method :content_encodings

      def octet_stream?(headers)
        header(headers, 'content-type').to_s.downcase.include?('application/octet-stream')
      end
      module_function :octet_stream?
      private_class_method :octet_stream?

      def header(headers, name)
        headers.fetch(name) do
          headers.find { |key, _value| key.to_s.casecmp?(name) }&.last
        end
      end
      module_function :header
      private_class_method :header
    end
  end
end
