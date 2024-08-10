# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # A DTO for an article.
    # It is used to store the extracted information of an article.
    #
    # TODO: make this the input for the Rss Builder
    class Article
      def initialize(**options)
        @to_h = options
      end

      def [](key)
        @to_h[key]
      end

      def []=(key, value)
        @to_h[key] = value
      end

      def keys
        @to_h.keys
      end

      def each(&)
        @to_h.each(&)
      end

      def respond_to_missing?(method_name, include_private = false)
        Log.debug "Article#respond_to_missing? #{method_name}"
        @to_h.key?(method_name) || super
      end
    end
  end
end
