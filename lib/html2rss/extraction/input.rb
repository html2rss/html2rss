# frozen_string_literal: true

module Html2rss
  module Extraction
    ##
    # The one place a host's +page+ and +responses+ are read: keys may be strings or symbols (JSON hosts send
    # strings), and a malformed entry is {InvalidError} data, never a +KeyError+ inside the scrapers.
    module Input
      # Raised when the host sent a page or an answer the kernel cannot read.
      class InvalidError < Html2rss::Error; end

      ##
      # @param page [Hash] +url+, +body+ and optionally +headers+
      # @return [Hash{Symbol => Object}]
      # @raise [InvalidError] when the page is not a hash or lacks +url+ or +body+
      def self.page(page) = entry(page, :url, :body)

      ##
      # @param responses [Hash] every answer so far, by request id
      # @return [Hash{String => Hash{Symbol => Object}}]
      # @raise [InvalidError] when an answer has neither +url+ and +body+ nor a known +error_kind+
      def self.responses(responses)
        raise InvalidError, "responses must be a hash, got #{responses.class}" unless responses.is_a?(Hash)

        responses.to_h { |id, answer| [id.to_s, answer(answer)] }
      end

      def self.answer(answer)
        hash = entry(answer)
        given = hash[:error_kind]
        return entry(hash, :url, :body) if given.nil?

        kind = given.to_s.to_sym
        raise InvalidError, "unknown error kind: #{given.inspect}" unless ErrorKind::ALL.key?(kind)

        { error_kind: kind }
      end
      private_class_method :answer

      def self.entry(entry, *required)
        raise InvalidError, "expected a hash, got #{entry.class}" unless entry.is_a?(Hash)

        entry.transform_keys(&:to_sym).tap do |hash|
          missing = required.reject { hash.key?(_1) }
          raise InvalidError, "missing #{missing.join(', ')}" unless missing.empty?
        end
      end
      private_class_method :entry
    end
  end
end
