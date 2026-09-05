# frozen_string_literal: true

module Html2rss
  class FeedPipeline
    ##
    # Feed-level request plan: +:auto+ (fallback chain) or a concrete transport strategy.
    #
    # {RequestService} executes concrete adapters only. +:auto+ is resolved here before
    # any session or adapter call — plan vs transport locality.
    class StrategyPlan
      # Feed-level auto plan: try {AutoFallback::CHAIN} until items are extracted.
      Auto = Data.define do
        # @return [Integer]
        def request_slots
          [AutoFallback::CHAIN.size - 1, 0].max
        end
      end

      # Concrete transport strategy name for {RequestService}.
      Concrete = Data.define(:strategy) do
        # @return [Integer]
        def request_slots = 0
      end

      # Symbol used in config / configure for the auto plan.
      AUTO_NAME = :auto

      class << self
        ##
        # @param name [Symbol, String] config or configure strategy value
        # @return [Auto, Concrete] resolved feed-level plan
        # @raise [ArgumentError] when +name+ is neither +:auto+ nor a registered strategy
        def resolve(name)
          normalized = name.to_sym
          return Auto.new if normalized == AUTO_NAME

          unless RequestService.strategy_registered?(normalized)
            raise ArgumentError, "unknown strategy plan: #{name.inspect}"
          end

          Concrete.new(strategy: normalized)
        end

        ##
        # Cheap single-request diagnostic default: +:auto+ → +:default+.
        # Does not run {AutoFallback}. Prefer {resolve} for scrape/capture feeds.
        #
        # @param name [Symbol, String, nil] plan name (+nil+ → +:auto+)
        # @return [Symbol] concrete {RequestService} strategy
        def concrete_for_diagnostic(name = AUTO_NAME)
          plan = resolve(name || AUTO_NAME)
          plan.is_a?(Auto) ? RequestService.default_strategy_name : plan.strategy
        end

        ##
        # @param name [Symbol, String, nil] candidate plan name
        # @return [Boolean] whether +name+ is a valid feed-level strategy plan
        def valid?(name)
          return false unless name.is_a?(Symbol) || name.is_a?(String)

          resolve(name)
          true
        rescue ArgumentError
          false
        end

        ##
        # @return [Array<Symbol>] accepted plan names (+:auto+ plus registered strategies)
        def accepted_names
          [AUTO_NAME, *RequestService.strategy_names.map(&:to_sym)].uniq
        end
      end
    end
  end
end
