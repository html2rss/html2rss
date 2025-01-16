# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Provides a namespace for attribute post processors.
    module AttributePostProcessors
      ##
      # All post processors must inherit from this base class and implement `self.validate_args!` and `#get`.
      class Base
        # Validates the presence of required options in the context
        #
        # @param keys [Array<Symbol>] the keys to check for presence
        # @param context [Hash] the context containing options
        # @raise [MissingOption] if any key is missing
        def self.expect_options(keys, context)
          keys.each do |key|
            unless (options = context[:options]).key?(key)
              raise MissingOption, "The `#{key}` option is missing in: #{options.inspect}", [],
                    cause: nil
            end
          end
        end

        # Asserts that the value is of the expected type(s)
        #
        # @param value [Object] the value to check
        # @param types [Array<Class>, Class] the expected type(s)
        # @param name [String] the name of the option being checked
        # @param context [Selectors::Context] the context
        # @raise [InvalidType] if the value is not of the expected type(s)
        def self.assert_type(value, types = [], name, context:)
          types = [types] unless types.is_a?(Array)

          return if types.any? { |type| value.is_a?(type) }

          options = context[:options] if context.is_a?(Hash)
          options ||= { file: File.basename(caller_locations(1, 1).first.absolute_path) }

          raise InvalidType, format('The type of `%<name>s` must be %<types>s, but is: %<type>s in: %<options>s',
                                    name:, types: types.join(' or '), type: value.class, options: options.inspect),
                [], cause: nil
        end

        ##
        # This method validates the arguments passed to the post processor. Must be implemented by subclasses.
        def self.validate_args!(_value, _context)
          raise NotImplementedError, 'You must implement the `validate_args!` method in the post processor'
        end

        ##
        # Shorthand method to instantiate the post processor and call `#get` on it
        def self.get(value, context) = new(value, context).get

        # Initializes the post processor
        #
        # @param value [Object] the value to be processed
        # @param context [Selectors::Context] the context
        def initialize(value, context)
          klass = self.class
          # TODO: get rid of Hash
          klass.assert_type(context, [Selectors::Context, Hash], 'context', context:)
          klass.validate_args!(value, context)

          @value = value
          @context = context
        end

        attr_reader :value, :context

        # Abstract method to be implemented by subclasses
        #
        # @raise [NotImplementedError] if not implemented in subclass
        def get
          raise NotImplementedError, 'You must implement the `get` method in the post processor'
        end
      end
    end
  end
end
