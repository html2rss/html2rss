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
        # Compiles and memoizes a gsub +pattern+ string as a Regexp.
        #
        # @param string [String]
        # @return [Regexp]
        def self.compiled_pattern(string)
          compiled_patterns[string] ||= compile_regexp_string(string)
        end

        # rubocop:disable-next ThreadSafety/ClassInstanceVariable
        def self.compiled_patterns
          @compiled_patterns ||= {}
        end
        private_class_method :compiled_patterns

        # Parses the given String and builds a Regexp out of it.
        #
        # It will remove one pair of surrounding slashes ('/') from the String
        # to maintain backwards compatibility before building the Regexp.
        #
        # @param string [String]
        # @return [Regexp]
        def self.compile_regexp_string(string)
          raise ArgumentError, 'must be a string!' unless string.is_a?(String)

          # Only remove surrounding slashes if the string has at least 3 characters
          # to avoid issues with single character strings like "/"
          source = string
          source = source[1..-2] if source.length >= 3 && source.start_with?('/') && source.end_with?('/')
          Regexp::Parser.parse(source, options: ::Regexp::EXTENDED | ::Regexp::IGNORECASE).to_re
        end
        private_class_method :compile_regexp_string

        ##
        # @param value [String]
        # @param context [Selectors::StepEnv]
        def initialize(value, context)
          super

          step_config = context.step_config

          @replacement = step_config[:replacement]
          @pattern = step_config[:pattern]
        end

        ##
        # @return [String]
        def call
          value.to_s.gsub(pattern, replacement)
        end

        private

        attr_accessor :replacement

        ##
        # @return [Regexp]
        def pattern
          raw = @pattern
          raw.is_a?(String) ? self.class.compiled_pattern(raw) : raw
        end
      end
    end
  end
end
