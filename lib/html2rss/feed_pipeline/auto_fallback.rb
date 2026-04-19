# frozen_string_literal: true

module Html2rss
  class FeedPipeline
    ##
    # Retries feed extraction across concrete request strategies for :auto mode.
    class AutoFallback
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

        strategies.each do |strategy|
          state, attempts, last_error = attempt(strategy:, attempts:, last_error:, budget:)
          return state if state
        end

        raise NoFeedItemsExtracted.new(attempts:) if zero_items_terminal?(attempts)
        raise last_error if last_error

        raise NoFeedItemsExtracted.new(attempts:)
      end

      private

      attr_reader :strategies, :budget, :session_for, :articles_for

      def attempt(strategy:, attempts:, last_error:, budget:)
        request_session = session_for.call(strategy:, budget:)
        response, attempts, last_error = fetch_response(
          request_session:,
          strategy:,
          attempts:,
          last_error:
        )
        return [nil, attempts, last_error] unless response

        process_response(response:, strategy:, attempts:, last_error:, request_session:)
      end

      def fetch_response(request_session:, strategy:, attempts:, last_error:)
        [request_session.fetch_initial_response, attempts, last_error]
      rescue *RequestService::AutoStrategy::NON_FALLBACK_ERRORS
        raise
      rescue StandardError => error
        attempts << { strategy:, items_count: nil, error_class: error.class.name }
        Log.debug("#{self.class}: strategy=#{strategy} error=#{error.class}: #{error.message}")
        [nil, attempts, error]
      end

      def process_response(response:, strategy:, attempts:, last_error:, request_session:)
        articles = articles_for.call(response:, request_session:)
        items_count = articles.size
        attempts << { strategy:, items_count:, error_class: nil }
        Log.debug("#{self.class}: strategy=#{strategy} items=#{items_count}")
        return [{ response:, articles: }, attempts, last_error] if items_count.positive?

        [nil, attempts, last_error]
      end

      def zero_items_terminal?(attempts)
        successful_counts = attempts.filter_map { _1[:items_count] }
        successful_counts.any? && successful_counts.all?(&:zero?)
      end
    end
  end
end
