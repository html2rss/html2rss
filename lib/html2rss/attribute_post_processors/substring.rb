# frozen_string_literal: true

module Html2rss
  module AttributePostProcessors
    ## Returns a defined part of a String.
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
      # @param value [String]
      # @param env [Item::Context]
      def initialize(value, env)
        @value = value
        @options = env[:options]
      end

      ##
      # @return [String]
      def get
        ending = @options.fetch(:end, @value.length).to_i
        @value[@options[:start].to_i..ending]
      end
    end
  end
end
