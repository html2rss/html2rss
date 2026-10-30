# frozen_string_literal: true

module Html2rss
  ##
  # Edge validation for caller-supplied option values (public API, CLI, MCP).
  # Everything past these checks may trust its types.
  module Option
    class << self
      ##
      # @param name [Symbol] option name used in the error message
      # @param value [Object] candidate value
      # @param min [Integer] inclusive lower bound
      # @param max [Integer, nil] inclusive upper bound
      # @param optional [Boolean] whether +nil+ passes through
      # @return [Integer, nil] +value+ when valid
      # @raise [InvalidOption] when +value+ is not an Integer within bounds
      def integer(name, value, min:, max: nil, optional: false)
        return value if value.nil? && optional
        return value if value.is_a?(Integer) && (min..max).cover?(value)

        raise InvalidOption, "#{name} must be an Integer in #{min}..#{max}, got #{value.inspect}"
      end

      ##
      # @param value [Symbol, String, nil] strategy plan name (+nil+ means +:auto+)
      # @return [Symbol] the plan name
      # @raise [InvalidOption] when +value+ is not a registered plan
      def strategy(value)
        name = value.nil? ? FeedPipeline::StrategyPlan::AUTO_NAME : value
        return name.to_sym if FeedPipeline::StrategyPlan.valid?(name)

        accepted = FeedPipeline::StrategyPlan.accepted_names.join(', ')
        raise InvalidOption, "strategy must be one of #{accepted}, got #{value.inspect}"
      end

      ##
      # @param name [Symbol] option name used in the error message
      # @param value [Object] candidate list
      # @return [Array] +value+ when it is a non-empty Array
      # @raise [InvalidOption] otherwise
      def list(name, value)
        return value if value.is_a?(Array) && value.any?

        raise InvalidOption, "#{name} must be a non-empty Array, got #{value.inspect}"
      end
    end
  end
end
