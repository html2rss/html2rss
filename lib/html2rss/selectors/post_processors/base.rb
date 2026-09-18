# frozen_string_literal: true

module Html2rss
  class Selectors
    module PostProcessors
      ##
      # All post processors must inherit from this base class and implement `#get`.
      # Declare +VALUE_TYPE+ when the extracted value must be a fixed Ruby type;
      # override +validate_args!+ only for semantic checks beyond that.
      class Base
        # Asserts that the value is of the expected type(s)
        #
        # @param value [Object] the value to check
        # @param types [Array<Class>, Class] the expected type(s)
        # @param name [String] the name of the option being checked
        # @param context [Selectors::StepEnv] call-site context used for richer validation errors
        # @return [void]
        # @raise [InvalidType] if the value is not of the expected type(s)
        def self.assert_type(value, types, name, context:)
          return if Array(types).any? { |type| value.is_a?(type) }

          message = "The type of `#{name}` must be #{Array(types).join(' or ')}, " \
                    "but is: #{value.class} in: #{context.options.inspect}"
          raise InvalidType, message, [], cause: nil
        end

        ##
        # Validates presence and types from the strategy's +OPTIONS+ contract.
        #
        # @param context [Selectors::StepEnv]
        # @return [void]
        # @raise [MissingOption] if a required option key is absent
        # @raise [InvalidType] if a present option has the wrong type
        def self.validate_options!(context)
          option_values = context.options || {}
          strategy_options.each { |spec| validate_option_spec!(spec, option_values, context) }
        end

        ##
        # @param spec [Selectors::OptionSpec]
        # @param option_values [Hash] post-processor YAML option keys
        # @param context [Selectors::StepEnv]
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
        # @return [Array<Selectors::OptionSpec>]
        def self.strategy_options
          const_defined?(:OPTIONS, false) ? const_get(:OPTIONS) : [].freeze
        end

        ##
        # Semantic / value checks beyond +VALUE_TYPE+ and the +OPTIONS+ contract.
        # Override in subclasses that need non-type checks (non-empty, item_env, …).
        #
        # @param _value [Object] extracted selector value
        # @param _context [Selectors::StepEnv] post-processor execution context
        # @return [void]
        def self.validate_args!(_value, _context)
          # no-op default
        end

        # Initializes the post processor
        #
        # @param value [Object] the value to be processed
        # @param context [Selectors::StepEnv] runtime selector context and options
        # @raise [InvalidType] if +context+ is not a {Selectors::StepEnv} or +VALUE_TYPE+ mismatches
        def initialize(value, context) # rubocop:disable Metrics/MethodLength -- type guard + VALUE_TYPE + validate_args
          unless context.is_a?(Selectors::StepEnv)
            raise InvalidType,
                  "The type of `context` must be #{Selectors::StepEnv}, but is: #{context.class}",
                  [], cause: nil
          end

          klass = self.class
          klass.validate_options!(context)
          klass.assert_type(value, klass::VALUE_TYPE, :value, context:) if klass.const_defined?(:VALUE_TYPE, false)
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
