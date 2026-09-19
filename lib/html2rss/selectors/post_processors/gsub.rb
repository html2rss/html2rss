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

        # Character cap for the authored +pattern+ string (before slash stripping).
        # Same unit as JSON Schema +maxLength+.
        MAX_PATTERN_LENGTH = 256

        # JSON Schema description exported via +schema_export+.
        DESCRIPTION = format(
          'Replace matches of `pattern` in the extracted string with `replacement` ' \
          '(Ruby String#gsub; pattern may be a regexp-like string). ' \
          'Patterns over %d characters as written, or with nested quantifiers, are rejected.',
          MAX_PATTERN_LENGTH
        ).freeze

        # Example post-process objects for JSON Schema +examples+.
        EXAMPLES = [
          { 'name' => 'gsub', 'pattern' => 'boo', 'replacement' => 'baz' }
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this post-processor
        def self.schema_export
          fragment = SchemaExport.for_post_processor(name: :gsub, klass: self)
          fragment.fetch(:properties).fetch(:pattern)[:maxLength] = MAX_PATTERN_LENGTH
          fragment
        end

        ##
        # Compiles and memoizes a gsub +pattern+ string as a Regexp.
        #
        # Raises before memoizing when the authored pattern exceeds
        # {MAX_PATTERN_LENGTH} characters, its star-height is greater than 1, or it does not parse.
        #
        # @param string [String]
        # @return [Regexp]
        # @raise [ArgumentError] when +string+ is not a String, exceeds the character cap,
        #   contains nested quantifiers, or does not parse
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
        # Length is the character count of the authored string (the JSON Schema
        # +maxLength+ unit), then the AST is walked for nested quantifiers,
        # then +to_re+. Parser errors are re-raised as ArgumentError so
        # validation and execution share one path.
        #
        # @param string [String]
        # @return [Regexp]
        # @raise [ArgumentError] when +string+ is not a String, exceeds {MAX_PATTERN_LENGTH},
        #   contains nested quantifiers, or does not parse
        def self.compile_regexp_string(string)
          raise ArgumentError, 'must be a string!' unless string.is_a?(String)
          raise ArgumentError, "pattern exceeds #{MAX_PATTERN_LENGTH} characters" if string.length > MAX_PATTERN_LENGTH

          source = regexp_source(string)

          expression = Regexp::Parser.parse(source, options: ::Regexp::EXTENDED | ::Regexp::IGNORECASE)
          raise ArgumentError, 'pattern contains nested quantifiers' if nested_quantifiers?(expression)

          expression.to_re
        rescue Regexp::Parser::Error => error
          raise ArgumentError, error.message, [], cause: nil
        end
        private_class_method :compile_regexp_string

        # Strips one pair of surrounding slashes when the source is long enough.
        #
        # @param string [String]
        # @return [String]
        def self.regexp_source(string)
          return string unless string.length >= 3 && string.start_with?('/') && string.end_with?('/')

          string[1..-2]
        end
        private_class_method :regexp_source

        # Star-height greater than 1: a quantified node whose subtree contains another.
        #
        # +each_expression+ yields +(node, index)+. Do not pass +&:quantified?+:
        # +Symbol#to_proc+ would forward the index into +quantified?+ (arity 0).
        #
        # @param expression [Regexp::Expression::Subexpression]
        # @return [Boolean]
        # rubocop:disable-next Style/SymbolProc
        def self.nested_quantifiers?(expression)
          expression.each_expression.any? do |node|
            node.quantified? && !node.terminal? && node.each_expression.any? { |child| child.quantified? }
          end
        end
        private_class_method :nested_quantifiers?

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
