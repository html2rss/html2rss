# frozen_string_literal: true

module Html2rss
  class Selectors
    module PostProcessors
      ##
      # All post processors must inherit from this base class and implement `self.validate_args!` and `#get`.
      class Base
        # Asserts that the value is of the expected type(s)
        #
        # @param value [Object] the value to check
        # @param types [Array<Class>, Class] the expected type(s)
        # @param name [String] the name of the option being checked
        # @param context [Selectors::Context] call-site context used for richer validation errors
        # @return [void]
        # @raise [InvalidType] if the value is not of the expected type(s)
        def self.assert_type(value, types, name, context:)
          return if Array(types).any? { |type| value.is_a?(type) }

          options = if context.respond_to?(:options)
                      context.options
                    else
                      { file: File.basename(caller(1, 1).first.split(':').first) }
                    end
          message = "The type of `#{name}` must be #{Array(types).join(' or ')}, " \
                    "but is: #{value.class} in: #{options.inspect}"
          raise InvalidType, message, [], cause: nil
        end

        ##
        # Validates presence and types from the strategy's +OPTIONS+ contract.
        #
        # @param context [Selectors::Context]
        # @return [void]
        # @raise [MissingOption] if a required option key is absent
        # @raise [InvalidType] if a present option has the wrong type
        def self.validate_options!(context)
          option_values = context.options || {}
          strategy_options.each { |spec| validate_option_spec!(spec, option_values, context) }
        end

        ##
        # @param spec [Selectors::Option]
        # @param option_values [Hash] post-processor YAML option keys
        # @param context [Selectors::Context]
        # @return [void]
        def self.validate_option_spec!(spec, option_values, context)
          unless option_values.key?(spec.name)
            return unless spec.required

            raise MissingOption, "The `#{spec.name}` option is missing in: #{option_values.inspect}", [],
                  cause: nil
          end

          value = option_values[spec.name]
          return if value.nil? && !spec.required

          assert_type(value, spec.type, spec.name, context:)
        end

        ##
        # @return [Array<Selectors::Option>]
        def self.strategy_options
          const_defined?(:OPTIONS, false) ? const_get(:OPTIONS) : [].freeze
        end

        ##
        # Semantic / value checks beyond the +OPTIONS+ type contract. Override in subclasses.
        #
        # @param _value [Object] extracted selector value
        # @param _context [Selectors::Context] post-processor execution context
        # @return [void]
        def self.validate_args!(_value, _context)
          # no-op default; subclasses add semantic checks (non-empty, item_scope, …)
        end

        # Initializes the post processor
        #
        # @param value [Object] the value to be processed
        # @param context [Selectors::Context] runtime selector context and options
        def initialize(value, context)
          klass = self.class
          klass.assert_type(context, Selectors::Context, 'context', context:)
          klass.validate_options!(context)
          klass.validate_args!(value, context)

          @value = value
          @context = context
        end

        attr_reader :value, :context

        # Abstract method to be implemented by subclasses
        #
        # @return [Object] transformed value
        # @raise [NotImplementedError] if not implemented in subclass
        def get
          raise NotImplementedError, 'You must implement the `get` method in the post processor'
        end
      end
    end
  end
end
