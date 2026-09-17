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
        # Expected Ruby class for the extracted value before this post-processor runs.
        VALUE_TYPE = String

        # Config-facing options contract (validator / SchemaDoc / Base.validate_options!).
        OPTIONS = [
          Option.new(name: :start, type: Integer),
          Option.new(name: :end, type: Integer, required: false)
        ].freeze

        # JSON Schema description exported via +schema_doc+.
        DESCRIPTION = 'Return a slice of the extracted string using Integer `start` and optional `end` ' \
                      '(Ruby String#[] range semantics; end may be omitted).'

        # Example post-process objects for JSON Schema +examples+.
        EXAMPLES = [
          { 'name' => 'substring', 'start' => 4, 'end' => 6 }
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this post-processor
        def self.schema_doc = SchemaDoc.for_post_processor(name: :substring, klass: self)

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
          options = context.options
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
