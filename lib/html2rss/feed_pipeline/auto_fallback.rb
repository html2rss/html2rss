# frozen_string_literal: true

module Html2rss
  class FeedPipeline
    ##
    # Retries feed extraction across concrete request strategies for :auto mode.
    class AutoFallback
      # Ordered list of concrete request strategies attempted by auto mode.
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
        RequestService::BrowserlessConfigurationError,
        RequestService::BotasaurusConfigurationError
      ].freeze

      ##
      # @param strategies [Array<Symbol>] ordered concrete strategies for fallback
      # @param budget [RequestService::Budget] shared request budget across retries
      # @param session_for [Proc] builds request session for strategy and budget
      # @param articles_for [Proc] extracts deduplicated articles for response and session
      def initialize(strategies:, budget:, session_for:, articles_for:)
        @strategies = strategies
        @budget = budget
        @session_for = session_for
        @articles_for = articles_for
      end

      ##
      # @return [Hash{Symbol => Object}] response/articles pipeline state
      def call
        attempts = []
        last_error = nil

        strategies.each_with_index do |strategy, index|
          state, attempts, last_error = attempt(
            strategy:,
            next_strategy: strategies[index + 1],
            attempts:,
            last_error:,
            budget:
          )
          return state if state
        end

        raise NoFeedItemsExtracted.new(attempts:) if zero_items_terminal?(attempts)
        raise last_error if last_error

        raise NoFeedItemsExtracted.new(attempts:)
      end

      private

      attr_reader :strategies, :budget, :session_for, :articles_for

      def attempt(strategy:, next_strategy:, attempts:, last_error:, budget:)
        request_session = session_for.call(strategy:, budget:)
        response, attempts, last_error = fetch_response(
          request_session:,
          strategy:,
          next_strategy:,
          attempts:,
          last_error:
        )
        return [nil, attempts, last_error] unless response

        process_response(response:, strategy:, next_strategy:, attempts:, last_error:, request_session:)
      end

      def fetch_response(request_session:, strategy:, next_strategy:, attempts:, last_error:)
        [request_session.fetch_initial_response, attempts, last_error]
      rescue *NON_FALLBACK_ERRORS
        raise
      rescue StandardError => error
        attempts << { strategy:, items_count: nil, error_class: error.class.name }
        log_info_fallback_error(strategy:, next_strategy:, error:) if next_strategy
        Log.debug("#{self.class}: strategy=#{strategy} error=#{error.class}: #{error.message}")
        [nil, attempts, error]
      end

      def process_response(response:, strategy:, next_strategy:, attempts:, last_error:, request_session:)
        articles = articles_for.call(response:, request_session:)
        items_count = articles.size
        attempts << { strategy:, items_count:, error_class: nil }
        Log.debug("#{self.class}: strategy=#{strategy} items=#{items_count}")
        return success_state(response:, strategy:, attempts:, last_error:, articles:) if items_count.positive?

        log_info_fallback_zero_items(strategy:, next_strategy:) if next_strategy
        [nil, attempts, last_error]
      end

      def success_state(response:, strategy:, attempts:, last_error:, articles:)
        if attempts.size > 1
          Log.info("#{self.class}: auto selected strategy=#{strategy} after attempts=#{attempts.size}")
        end

        [{ response:, articles: }, attempts, last_error]
      end

      def zero_items_terminal?(attempts)
        successful_counts = attempts.filter_map { _1[:items_count] }
        successful_counts.any? && successful_counts.all?(&:zero?)
      end

      def log_info_fallback_error(strategy:, next_strategy:, error:)
        Log.info(
          "#{self.class}: auto fallback #{strategy} -> #{next_strategy} " \
          "after error=#{error.class}"
        )
      end

      def log_info_fallback_zero_items(strategy:, next_strategy:)
        Log.info(
          "#{self.class}: auto fallback #{strategy} -> #{next_strategy} " \
          'after zero extracted items'
        )
      end
    end
  end
end
