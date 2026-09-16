# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # One config-facing option on an extractor or post-processor strategy.
    #
    # Strategies own an +OPTIONS+ Array of these; validator, SchemaDoc, and
    # post-processor Base consume that single contract (no parallel OPTION_TYPES maps).
    Option = Data.define(:name, :type, :required) do
      # @param name [Symbol, String]
      # @param type [Class, Array<Class>]
      # @param required [Boolean]
      def initialize(name:, type:, required: true)
        super(name: name.to_sym, type:, required:)
      end
    end
  end
end
