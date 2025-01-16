# frozen_string_literal: true

module Html2rss
  class Selectors
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
      class Gsub < Base
        def self.validate_args!(value, context)
          assert_type value, String, :value, context:
          expect_options(%i[replacement pattern], context)
          assert_type context.dig(:options, :replacement), [String, Hash], :replacement, context:
        end

        ##
        # @param value [String]
        # @param context [Selectors::Context]
        def initialize(value, context)
          super

          options = context[:options]

          @replacement = options[:replacement]
          @pattern = options[:pattern]
        end

        ##
        # @return [String]
        def get
          value.to_s.gsub(pattern, replacement)
        end

        private

        attr_accessor :replacement

        ##
        # @return [Regexp]
        def pattern
          @pattern.is_a?(String) ? Utils.build_regexp_from_string(@pattern) : @pattern
        end
      end
    end
  end
end
