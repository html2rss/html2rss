# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Strategy orchestrator that retries across concrete transports.
    class AutoStrategy < Strategy
      # Ordered list of concrete request strategies attempted by auto mode.
      CHAIN = %i[faraday botasaurus browserless].freeze

      # Error classes that should abort auto fallback immediately.
      NON_FALLBACK_ERRORS = [
        UnknownStrategy,
        InvalidUrl,
        UnsupportedUrlScheme,
        UnsupportedResponseContentType,
        RequestBudgetExceeded,
        PrivateNetworkDenied,
        CrossOriginFollowUpDenied,
        ResponseTooLarge,
        BrowserlessConfigurationError,
        BotasaurusConfigurationError
      ].freeze

      ##
      # Executes a tiered request strategy and pins the winner on success.
      #
      # @return [Response] normalized request response
      # @raise [StandardError] last fallback-eligible failure when all tiers fail
      def execute
        return execute_pinned(ctx.selected_strategy) if ctx.selected_strategy

        fallback_chain
      end

      private

      def execute_pinned(strategy_name)
        log_debug("pinned strategy=#{strategy_name} relation=#{ctx.relation} url=#{ctx.url}")
        RequestService.execute(ctx, strategy: strategy_name)
      end

      def fallback_chain
        last_error = nil

        CHAIN.each do |strategy_name|
          response, last_error = attempt_with_fallback(strategy_name:, last_error:)
          return response if response
        end

        raise last_error if last_error

        raise UnknownStrategy, 'Auto strategy has no concrete strategies configured.'
      end

      def attempt_with_fallback(strategy_name:, last_error:)
        [execute_and_pin(strategy_name), last_error]
      rescue *NON_FALLBACK_ERRORS
        raise
      rescue StandardError => error
        log_debug("fallback strategy=#{strategy_name} error=#{error.class}: #{error.message}")
        [nil, error]
      end

      def execute_and_pin(strategy_name)
        log_debug("attempt strategy=#{strategy_name} relation=#{ctx.relation} url=#{ctx.url}")
        RequestService.execute(ctx, strategy: strategy_name).tap do
          ctx.selected_strategy = strategy_name
          log_debug("success strategy=#{strategy_name} relation=#{ctx.relation} url=#{ctx.url}")
        end
      end

      def log_debug(message)
        Html2rss::Log.debug("#{self.class}: #{message}")
      end
    end
  end
end
