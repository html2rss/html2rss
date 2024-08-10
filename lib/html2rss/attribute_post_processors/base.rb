# frozen_string_literal: true

module Html2rss
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
      # @raise [InvalidType] if the value is not of the expected type(s)
      def self.assert_type(value, types = [], name)
        types = [types] unless types.is_a?(Array)

        return if types.any? { |type| value.is_a?(type) }

        error_message_template = 'The type of `%s` must be %s, but is: %s'
        raise InvalidType, format(error_message_template, name, types.join(' or '), value.class), [], cause: nil
      end

      # private_class_method :expect_options, :assert_type

      ##
      # This method validates the arguments passed to the post processor. Must be implemented by subclasses.
      def self.validate_args!(_value, _context)
        raise NotImplementedError, 'You must implement the `validate_args!` method in the post processor'
      end

      # Initializes the post processor
      #
      # @param value [Object] the value to be processed
      # @param context [Item::Context] the context
      def initialize(value, context)
        klass = self.class
        # TODO: get rid of Hash
        klass.assert_type(context, [Item::Context, Hash], 'context')
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
