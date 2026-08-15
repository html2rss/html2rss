# frozen_string_literal: true

module Html2rss
  class Selectors
    module PostProcessors
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
      class Substring < Base
        # Required config field types (validator introspection via +Options+).
        OPTION_TYPES = { start: Integer }.freeze

        # Optional config field types (validated when the key is present and non-nil).
        OPTIONAL_OPTION_TYPES = { end: Integer }.freeze

        # Config fields required by this post-processor (validator / schema introspection).
        Options = Struct.new(*OPTION_TYPES.keys, keyword_init: true)

        # JSON Schema description exported via +schema_doc+.
        DESCRIPTION = 'Return a slice of the extracted string using Integer `start` and optional `end` ' \
                      '(Ruby String#[] range semantics; end may be omitted).'

        # Example post-process objects for JSON Schema +examples+.
        EXAMPLES = [
          { 'name' => 'substring', 'start' => 4, 'end' => 6 }
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this post-processor
        def self.schema_doc = SchemaDoc.for_post_processor(name: :substring, klass: self)

        # @param value [String] extracted selector value
        # @param context [Selectors::Context] post-processor context
        # @return [void]
        def self.validate_args!(value, context)
          assert_type(value, String, :value, context:)

          options = context[:options]
          assert_type(options[:start], Integer, :start, context:)
          assert_type(options[:end], Integer, :end, context:) if options.key?(:end)
        end

        ##
        # Extracts the substring from the original string based on the provided start and end indices.
        #
        # @return [String, nil] The extracted substring.
        def get
          value[range]
        end

        ##
        # Determines the range for the substring extraction based on the provided start and end indices.
        #
        # @return [Range] The range object representing the start and end/Infinity (integers).
        def range
          options = context[:options]
          start = options[:start]

          return (start..) unless options.key?(:end)

          finish = options[:end]
          raise ArgumentError, 'The `start` value must be unequal to the `end` value.' if start == finish

          (start..finish)
        end
      end
    end
  end
end
