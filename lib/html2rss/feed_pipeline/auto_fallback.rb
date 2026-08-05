# frozen_string_literal: true

module Html2rss
  class FeedPipeline
    # Retries feed extraction across concrete request strategies for the :auto plan.
    #
    # Owned by {FeedPipeline}; invoked only after {StrategyPlan} resolves +:auto+.
    class AutoFallback
      # Ordered list of concrete request strategies attempted by the :auto plan.
      CHAIN = %i[faraday botasaurus browserless].freeze

      # Error classes that should abort auto fallback immediately.
      NON_FALLBACK_ERRORS = [
        RequestService::UnknownStrategy,
        RequestService::InvalidUrl,
        RequestService::UnsupportedUrlScheme,
        RequestService::UnsupportedResponseContentType,
        RequestService::RequestBudgetExceeded,
        RequestService::PrivateNetworkDenied,
        RequestService::CrossOriginFollowUpDenied,
        RequestService::ResponseTooLarge,
        RequestService::BrowserlessConfigurationError
      ].freeze

      ##
      # Mutable run state for one auto-fallback chain: attempts plus selected result.
      class AttemptState
        attr_reader :attempts, :result

        def initialize
          @attempts = []
          @result = nil
        end

        # @return [Boolean] true when a strategy already yielded items
        def succeeded? = !result.nil?

        # @param strategy [Symbol] strategy that raised
        # @param error [Exception] caught error
        # @return [void]
        def record_error(strategy:, error:)
          @attempts << { strategy:, items_count: nil, error_class: error.class.name }
        end

        # @param strategy [Symbol] strategy that returned a response
        # @param items_count [Integer] extracted article count
        # @return [void]
        def record_items(strategy:, items_count:)
          @attempts << { strategy:, items_count:, error_class: nil }
        end

        # @param response [RequestService::Response] successful response
        # @param articles [Array] extracted articles
        # @return [void]
        def succeed!(response:, articles:)
          @result = { response:, articles: }
        end
      end

      ##
      # @param strategies [Array<Symbol>] ordered concrete strategies for fallback
      # @param budget [RequestService::Budget] shared request budget across retries
      # @param session_for [Proc] request session factory proc
      # @param articles_for [Proc] article extraction proc
      # @return [void]
      def initialize(strategies:, budget:, session_for:, articles_for:)
        @strategies = strategies
        @budget = budget
        @session_for = session_for
        @articles_for = articles_for
      end

      ##
      # @return [Hash{Symbol => Object}] pipeline state containing :response and :articles
      def call
        state = run_attempts
        return state.result if state.succeeded?

        finalize_failure(attempts: state.attempts)
      end

      private

      attr_reader :strategies, :budget, :session_for, :articles_for

      def run_attempts
        AttemptState.new.tap do |state|
          strategies.each_with_index do |strategy, index|
            attempt(strategy:, next_strategy: strategies[index + 1], state:)
            break if state.succeeded?
          end
        end
      end

      def attempt(strategy:, next_strategy:, state:)
        request_session = session_for.call(strategy:, budget:)
        response = fetch_response(request_session:, strategy:, next_strategy:, state:)
        return unless response

        process_response(response:, strategy:, next_strategy:, request_session:, state:)
      end

      def fetch_response(request_session:, strategy:, next_strategy:, state:)
        request_session.fetch_initial_response
      rescue *NON_FALLBACK_ERRORS
        raise
      rescue StandardError => error
        state.record_error(strategy:, error:)
        log_warn_fallback_error(strategy:, next_strategy:, error:) if next_strategy
        Log.debug("#{self.class}: strategy=#{strategy} error=#{error.class}: #{error.message}")
        nil
      end

      def process_response(response:, strategy:, next_strategy:, request_session:, state:)
        articles = articles_for.call(response:, request_session:)
        items_count = articles.size
        state.record_items(strategy:, items_count:)
        Log.debug("#{self.class}: strategy=#{strategy} items=#{items_count}")
        return record_success(response:, strategy:, articles:, state:) if items_count.positive?

        log_info_fallback_zero_items(strategy:, next_strategy:) if next_strategy
      end

      def record_success(response:, strategy:, articles:, state:)
        state.succeed!(response:, articles:)
        return unless state.attempts.size > 1

        Log.info("#{self.class}: auto selected strategy=#{strategy} after attempts=#{state.attempts.size}")
      end

      def finalize_failure(attempts:)
        raise NoFeedItemsExtracted.new(attempts:)
      end

      def log_warn_fallback_error(strategy:, next_strategy:, error:)
        Log.warn("#{self.class}: auto fallback #{strategy} -> #{next_strategy} after error=#{error.class}")
      end

      def log_info_fallback_zero_items(strategy:, next_strategy:)
        Log.info("#{self.class}: auto fallback #{strategy} -> #{next_strategy} after zero extracted items")
      end
    end
  end
end
