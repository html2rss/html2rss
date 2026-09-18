# frozen_string_literal: true

require 'regexp_parser'

module Html2rss
  class Selectors
    module PostProcessors
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
        # Expected Ruby class for the extracted value before this post-processor runs.
        VALUE_TYPE = String

        # Config-facing options contract (validator / SchemaExport / Base.validate_options!).
        OPTIONS = [
          OptionSpec.new(name: :pattern, type: String),
          OptionSpec.new(name: :replacement, type: [String, Hash])
        ].freeze

        # JSON Schema description exported via +schema_export+.
        DESCRIPTION = 'Replace matches of `pattern` in the extracted string with `replacement` ' \
                      '(Ruby String#gsub; pattern may be a regexp-like string).'

        # Example post-process objects for JSON Schema +examples+.
        EXAMPLES = [
          { 'name' => 'gsub', 'pattern' => 'boo', 'replacement' => 'baz' }
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this post-processor
        def self.schema_export = SchemaExport.for_post_processor(name: :gsub, klass: self)

        ##
        # @param value [String]
        # @param context [Selectors::StepEnv]
        def initialize(value, context)
          super

          options = context.options

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
          @pattern.is_a?(String) ? parse_regexp_string(@pattern) : @pattern
        end

        ##
        # Parses the given String and builds a Regexp out of it.
        #
        # It will remove one pair of surrounding slashes ('/') from the String
        # to maintain backwards compatibility before building the Regexp.
        #
        # @param string [String]
        # @return [Regexp]
        def parse_regexp_string(string)
          raise ArgumentError, 'must be a string!' unless string.is_a?(String)

          # Only remove surrounding slashes if the string has at least 3 characters
          # to avoid issues with single character strings like "/"
          string = string[1..-2] if string.length >= 3 && string.start_with?('/') && string.end_with?('/')
          Regexp::Parser.parse(string, options: ::Regexp::EXTENDED | ::Regexp::IGNORECASE).to_re
        end
      end
    end
  end
end
