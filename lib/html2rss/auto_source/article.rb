# frozen_string_literal: true

require 'zlib'
require 'sanitize'

module Html2rss
  class AutoSource
    ##
    # A DTO for an article.
    # It is used to store the extracted information of an article.
    #
    # TODO: make this the input for the Rss Builder
    # TODO: make this become strict on options, to allow refactoring. this is glue code.
    # TODO: it can handle the id generation of any extractor sourced article
    class Article
      def initialize(**options)
        @to_h = {}
        options.each_pair { |key, value| self[key] = value }
      end

      def valid?
        !url.to_s.empty? && !title.to_s.empty? && !id.to_s.empty?
      end

      def [](key)
        @to_h[key.to_sym]
      end

      def []=(key, value)
        @to_h[key.to_sym] = value.freeze
      end

      def keys
        @to_h.keys
      end

      def each(&)
        @to_h.each(&)
      end

      def title
        @to_h[:title]
      end

      def description
        # TODO: reuse Postprocessor Sanitize
        Sanitize.fragment(@to_h[:description])
      end

      # @return [Addressable::URI, nil]
      def url
        Html2rss::Utils.sanitize_url(@to_h[:url] || @to_h[:link] || @to_h[:source_url])
      end

      def id
        @to_h[:id]
      end

      # @return [Addressable::URI, nil]
      def image
        Html2rss::Utils.sanitize_url @to_h[:image]
      end

      def guid
        Zlib.crc32([url, id].uniq.join('#!/'))
      end

      def published_at
        @to_h[:published_at]
      end

      # :reek:BooleanParameter { enabled: false }
      def respond_to_missing?(method_name, include_private = false)
        @to_h.key?(method_name.to_sym) || super
      end

      def method_missing(method_name, *args, &)
        method_name = method_name.to_sym

        if @to_h.key?(method_name)
          Log.info "Article#method_missing #{method_name}"
          return @to_h[method_name]
        end

        super
      end
    end
  end
end
