# frozen_string_literal: true

require 'to_regexp'

module Html2rss
  module AttributePostProcessors
    ##
    #
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
    # `pattern` can be a Regexp or a String.
    #
    # `replacement` can be a String or a Hash.
    #
    # See the doc on [String#gsub](https://ruby-doc.org/core/String.html#method-i-gsub) for more info.
    class Gsub
      ##
      # @param value [String]
      # @param env [Item::Context]
      def initialize(value, env)
        @value = value
        options = env[:options]
        pattern = options[:pattern]
        @pattern = pattern.to_regexp || pattern
        @replacement = options[:replacement]
      end

      ##
      # @return [String]
      def get
        @value.to_s.gsub(@pattern, @replacement)
      end
    end
  end
end
