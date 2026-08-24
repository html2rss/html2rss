# frozen_string_literal: true

module Html2rss
  class FeedPipeline
    # Retries feed extraction across concrete request strategies for the :auto plan.
    #
    # Owned by {FeedPipeline}; invoked only after {StrategyPlan} resolves +:auto+.
    # Hosted by the pipeline instance: session + extract call back into FeedPipeline.
    class AutoFallback # rubocop:disable Metrics/ClassLength -- attempt state + logging stay co-located
      # Ordered list of concrete request strategies attempted by the :auto plan.
      CHAIN = %i[faraday botasaurus].freeze

      # Error classes that should abort auto fallback immediately.
      NON_FALLBACK_ERRORS = [
        RequestService::UnknownStrategy,
        RequestService::InvalidUrl,
        RequestService::UnsupportedUrlScheme,
        RequestService::RequestBudgetExceeded,
        RequestService::PrivateNetworkDenied,
        RequestService::CrossOriginFollowUpDenied,
        RequestService::ResponseTooLarge
      ].freeze

      ##
      # Mutable run state for one auto-fallback chain: attempts plus selected result.
      class AttemptState
        attr_reader :attempts, :result, :last_response

        def initialize
          @attempts = []
          @result = nil
          @last_response = nil
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
        # @param transport_meta [Hash, nil] optional allowlisted upstream telemetry
        # @return [void]
        def record_items(strategy:, items_count:, transport_meta: nil)
          attempt = { strategy:, items_count:, error_class: nil }
          attempt[:transport_meta] = transport_meta if transport_meta && !transport_meta.empty?
          @attempts << attempt
        end

        # @param response [RequestService::Response] last response that reached extraction
        # @return [void]
        def remember_response(response)
          @last_response = response
        end

        # @param response [RequestService::Response] successful response
        # @param articles [Array] extracted articles
        # @param dedup_dropped [Integer] articles removed by deduplication
        # @param selected_strategy [Symbol] concrete strategy that produced items
        # @param attempt_count [Integer] number of attempts recorded for this chain
        # @param admission_drops [Hash{String => Integer}] Cleanup drop tallies
        # @return [void]
        # rubocop:disable Metrics/ParameterLists -- PipelineOutcome kwargs stay co-located
        def succeed!(response:, articles:, dedup_dropped:, selected_strategy:, attempt_count:,
                     admission_drops: {})
          @result = PipelineOutcome.new(
            response:,
            articles:,
            dedup_dropped:,
            selected_strategy:,
            attempt_count:,
            strategy_attempts: attempts,
            admission_drops:
          )
        end
        # rubocop:enable Metrics/ParameterLists
      end

      ##
      # @param strategies [Array<Symbol>] ordered concrete strategies for fallback
      # @param budget [RequestService::Budget] shared request budget across retries
      # @param pipeline [Html2rss::FeedPipeline] host for session + article extraction
      # @param config [Html2rss::Config] validated feed config
      # @param resources [Html2rss::FeedPipeline::RuntimePolicy::Resources] budget + policy
      # @return [void]
      def initialize(strategies:, budget:, pipeline:, config:, resources:)
        @strategies = strategies
        @budget = budget
        @pipeline = pipeline
        @config = config
        @resources = resources
      end

      ##
      # @return [Html2rss::FeedPipeline::PipelineOutcome] scrape-finished state for materialization
      def call
        state = run_attempts
        return state.result if state.succeeded?

        finalize_failure(attempts: state.attempts, response: state.last_response)
      end

      private

      attr_reader :strategies, :budget, :pipeline, :config, :resources

      def run_attempts
        AttemptState.new.tap do |state|
          strategies.each_with_index do |strategy, index|
            attempt(strategy:, next_strategy: strategies[index + 1], state:)
            break if state.succeeded?
          end
        end
      end

      def attempt(strategy:, next_strategy:, state:)
        request_session = pipeline.request_session_for(config, strategy:, resources:)
        response = fetch_response(request_session:, strategy:, next_strategy:, state:)
        return unless response

        process_response(response:, strategy:, next_strategy:, request_session:, state:)
      rescue RequestService::UnsupportedResponseContentType => error
        state.record_error(strategy:, error:)
        log_fallback_error(strategy:, next_strategy:, error:, request_session:) if next_strategy
      end

      def fetch_response(request_session:, strategy:, next_strategy:, state:)
        request_session.fetch_initial_response
      rescue *NON_FALLBACK_ERRORS
        raise
      rescue StandardError => error
        state.record_error(strategy:, error:)
        log_fallback_error(strategy:, next_strategy:, error:, request_session:) if next_strategy
        nil
      end

      def process_response(response:, strategy:, next_strategy:, request_session:, state:) # rubocop:disable Metrics/MethodLength -- extract + success path
        articles, dedup_dropped, admission_drops = articles_for(response:, request_session:)
        state.remember_response(response)
        items_count = articles.size
        state.record_items(strategy:, items_count:, transport_meta: response.transport_meta)
        Log.debug("#{self.class}: strategy=#{strategy} items=#{items_count} " \
                  "host=#{response.url.host} elapsed=#{format('%.3f', budget.elapsed_seconds)}s " \
                  "budget_remaining=#{budget_remaining_label}")
        if items_count.positive?
          return record_success(response:, strategy:, articles:, dedup_dropped:, admission_drops:,
                                state:)
        end

        log_info_fallback_zero_items(strategy:, next_strategy:, response:) if next_strategy
      end

      def articles_for(response:, request_session:)
        pipeline.deduplicated_articles(config:, response:, request_session:)
      end

      # rubocop:disable Metrics/ParameterLists -- success kwargs match PipelineOutcome
      def record_success(response:, strategy:, articles:, dedup_dropped:, admission_drops:, state:)
        attempt_count = state.attempts.size
        state.succeed!(response:, articles:, dedup_dropped:, selected_strategy: strategy,
                       attempt_count:, admission_drops:)
        return unless attempt_count > 1

        Log.info("#{self.class}: auto selected strategy=#{strategy} after attempts=#{attempt_count} " \
                 "host=#{response.url.host} elapsed=#{format('%.3f', budget.elapsed_seconds)}s " \
                 "budget_remaining=#{budget_remaining_label}")
      end
      # rubocop:enable Metrics/ParameterLists

      def finalize_failure(attempts:, response:)
        surface_category = empty_surface_category(response)
        raise NoFeedItemsExtracted.new(attempts:, surface_category:)
      end

      def empty_surface_category(response)
        return unless response
        return :unsupported_surface if response.feed_response?

        AutoSource::Scraper.classify_no_scraper_surface(response.parsed_body, body: response.body)
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def log_fallback_error(strategy:, next_strategy:, error:, request_session:)
        host = request_session.url.host
        detail = "host=#{host} elapsed=#{format('%.3f', budget.elapsed_seconds)}s " \
                 "budget_remaining=#{budget_remaining_label}"
        if error.is_a?(RequestService::RequestTimedOut)
          Log.info("#{self.class}: auto fallback #{strategy} -> #{next_strategy} " \
                   "after timeout=#{error.class} #{detail}")
        else
          Log.warn("#{self.class}: auto fallback #{strategy} -> #{next_strategy} " \
                   "after error=#{error.class} #{detail}")
        end
        Log.debug("#{self.class}: strategy=#{strategy} error=#{error.class}: #{error.message} #{detail}")
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      def log_info_fallback_zero_items(strategy:, next_strategy:, response:)
        Log.info("#{self.class}: auto fallback #{strategy} -> #{next_strategy} after zero extracted items " \
                 "host=#{response.url.host} elapsed=#{format('%.3f', budget.elapsed_seconds)}s " \
                 "budget_remaining=#{budget_remaining_label}")
      end

      def budget_remaining_label
        remaining = budget.remaining_timeout_seconds
        remaining.nil? ? 'untracked' : format('%.3f', remaining)
      end
    end
  end
end
