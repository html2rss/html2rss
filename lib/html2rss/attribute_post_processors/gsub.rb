# frozen_string_literal: true

module Html2rss
  module AttributePostProcessors
    ##
    # Imagine this HTML:
    #    <h1>Foo bar and boo<h1>
    #
    # YAML usage example:
    #    selectors:
    #      title:
    #        selector: h1
    #        post_process:
    #          name: gsub
    #          pattern: boo
    #          replacement: baz
    #
    # Would return:
    #    'Foo bar and baz'
    #
    # `pattern` can be a Regexp or a String. If it is a String, it will remove
    # one pair of surrounding slashes ('/') to keep backwards compatibility
    # and then parse it to build a Regexp.
    #
    # `replacement` can be a String or a Hash.
    #
    # See the doc on [String#gsub](https://ruby-doc.org/core/String.html#method-i-gsub) for more info.
    class Gsub
      ##
      # @param value [String]
      # @param context [Item::Context]
      def initialize(value, context)
        @value = value
        @options = context[:options]
      end

      ##
      # @return [String]
      def get
        @value.to_s.gsub(pattern, replacement)
      end

      private

      ##
      # @return [Regexp]
      def pattern
        pattern = @options[:pattern]
        raise ArgumentError, 'The `pattern` option is missing' unless pattern

        pattern.is_a?(String) ? Utils.build_regexp_from_string(pattern) : pattern
      end

      ##
      # @return [Hash, String]
      def replacement
        replacement = @options[:replacement]
        return replacement if replacement.is_a?(String) || replacement.is_a?(Hash)

        raise ArgumentError, 'The `replacement` option must be a String or Hash'
      end
    end
  end
end
