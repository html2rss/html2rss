# frozen_string_literal: true

module Html2rss
  module AttributePostProcessors
    ##
    # Returns a defined part of a String.
    #
    # Both parameters must be an Integer and they can be negative.
    # The +end+ parameter can be omitted, in that case it will not cut the
    # String at the end.
    #
    # A Regexp or a MatchString is not supported.
    #
    # See the [`String#[]`](https://ruby-doc.org/core/String.html#method-i-5B-5D)
    # documentation for more information.
    #
    # Imagine this HTML:
    #    <h1>Foo bar and baz<h1>
    #
    # YAML usage example:
    #    selectors:
    #      title:
    #        selector: h1
    #        post_process:
    #          name: substring
    #          start: 4
    #          end: 6
    #
    # Would return:
    #    'bar'
    class Substring
      ##
      # @param value [String] The original string to extract a substring from.
      # @param env [Item::Context] Context object providing additional environment details.
      def initialize(value, env)
        @value = value
        @options = env[:options]
      end

      ##
      # Extracts the substring from the original string based on the provided start and end indices.
      #
      # @return [String] The extracted substring.
      def get
        start_index = @options[:start].to_i
        end_index = @options[:end]&.to_i || @value.length

        @value[start_index..end_index]
      end
    end
  end
end
