# frozen_string_literal: true

require 'json'

module Html2rss
  class FeedPipeline
    # Retries feed extraction across concrete request strategies for the :auto plan.
    #
    # Owned by {FeedPipeline}; invoked only after {StrategyPlan} resolves +:auto+.
    # Hosted by the pipeline instance: session + extract call back into FeedPipeline.
    class AutoFallback # rubocop:disable Metrics/ClassLength -- attempt state + logging stay co-located
      # Ordered list of concrete request strategies attempted by the :auto plan.
      CHAIN = %i[default botasaurus].freeze

      # Deterministic HTTP statuses that indicate permanent failure rather than anti-bot challenges.
      DETERMINISTIC_HTTP_STATUSES = Set[400, 404, 410, 422, 451].freeze

      # Error classes that should abort auto fallback immediately.
      NON_FALLBACK_ERRORS = [
        RequestService::UnknownStrategy,
        RequestService::InvalidUrl,
        RequestService::UnsupportedUrlScheme,
        RequestService::RequestBudgetExceeded,
        RequestService::PrivateNetworkDenied,
        RequestService::CrossOriginFollowUpDenied,
        RequestService::ResponseTooLarge,
        RequestService::RedirectLimitReached
      ].freeze

      # Transport failures preserved across a later hop that extracts zero items.
      # Re-raised from finalize_failure so web maps them to uncacheable gateway/blocked
      # decisions instead of EXTRACTION_EMPTY.
      TERMINAL_TRANSPORT_ERRORS = [
        RequestService::RequestTimedOut,
        RequestService::BlockedSurfaceDetected,
        RequestService::ConnectionFailed
      ].freeze

      # One strategy attempt: the strategy, its successor, its session and the chain's run state.
      Hop = Data.define(:strategy, :next_strategy, :request_session, :state)

      ##
      # Mutable run state for one auto-fallback chain: attempts plus selected result.
      class AttemptState
        attr_reader :attempts, :result, :last_response, :last_error, :entry_resolution,
                    :terminal_transport_error

        def initialize
          @attempts = []
          @result = nil
          @last_response = nil
          @last_error = nil
          @terminal_transport_error = nil
          @entry_resolution = nil
          @resolution_tried = false
          @aborted = false
        end

        # @return [Boolean] true when a strategy already yielded items
        def succeeded? = !result.nil?

        # @return [Boolean] whether attempts were aborted due to deterministic errors
        def aborted? = @aborted

        # @return [void]
        def abort!
          @aborted = true
        end

        # @return [Boolean] whether entry resolution already ran for this chain
        def resolution_tried? = @resolution_tried

        # Records the diagnostic and marks the tournament as run for this chain.
        #
        # @param result [Html2rss::FeedResolution::Result]
        # @return [void]
        def remember_entry_resolution(result)
          @resolution_tried = true
          @entry_resolution = FeedResolution::Diag.from_result(result)
        end

        # @param strategy [Symbol] strategy that raised
        # @param error [Exception] caught error
        # @param elapsed_ms [Integer, nil] monotonic hop duration in milliseconds
        # @return [void]
        def record_error(strategy:, error:, elapsed_ms: nil)
          meta = error.transport_meta if error.is_a?(Error)
          append_attempt(strategy:, error_class: error.class.name, transport_meta: meta, elapsed_ms:)
          @last_error = error
          return unless TERMINAL_TRANSPORT_ERRORS.any? { |klass| error.is_a?(klass) }

          @terminal_transport_error = error
        end

        # @param strategy [Symbol] strategy that returned a response
        # @param items_count [Integer] extracted article count
        # @param transport_meta [Hash, nil] optional allowlisted upstream telemetry
        # @param elapsed_ms [Integer, nil] monotonic hop duration in milliseconds
        # @return [void]
        def record_items(strategy:, items_count:, transport_meta: nil, elapsed_ms: nil)
          @last_error = nil
          append_attempt(strategy:, items_count:, transport_meta:, elapsed_ms:)
        end

        # @param response [RequestService::Response] last response that reached extraction
        # @return [void]
        def remember_response(response)
          @last_response = response
        end

        # @param response [RequestService::Response] successful response
        # @param extraction [Html2rss::FeedPipeline::Extraction] its articles, drops and feed channel facts
        # @param selected_strategy [Symbol] concrete strategy that produced items
        # @param attempt_count [Integer] number of attempts recorded for this chain
        # @param scrape_target [Html2rss::ScrapeTarget]
        # @return [void]
        def succeed!(response:, extraction:, selected_strategy:, attempt_count:, scrape_target:)
          @result = PipelineOutcome.new(
            response:, selected_strategy:, attempt_count:, strategy_attempts: attempts,
            scrape_target:, entry_resolution:, **extraction.to_h
          )
        end

        # Raises the terminal transport error, last error, or NoFeedItemsExtracted with attempts attached.
        #
        # @return [void] always raises
        # @raise [Html2rss::Error, StandardError]
        def raise_failure!
          if (error = failure_error)
            error.attempts = attempts if error.is_a?(Error)
            raise error
          end

          response = @last_response
          surface_category = PageRecon.surface_category_for(response:, url: response.url) if response
          raise FeedPipeline.empty_feed_error(attempts:, surface_category:)
        end

        private

        def append_attempt(strategy:, items_count: nil, error_class: nil, transport_meta: nil, elapsed_ms: nil)
          attempt = { strategy:, items_count:, error_class: }
          attempt[:elapsed_ms] = elapsed_ms unless elapsed_ms.nil?
          attempt[:transport_meta] = transport_meta if transport_meta&.any?
          @attempts << attempt
        end

        def failure_error
          return @terminal_transport_error if @terminal_transport_error
          return if @last_error.nil? || @last_error.is_a?(RequestService::BotasaurusConfigurationError)

          @last_error
        end
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
        @scrape_target = ScrapeTarget.from_config(config)
      end

      ##
      # @return [Html2rss::FeedPipeline::PipelineOutcome] scrape-finished state for materialization
      def call
        state = run_attempts
        return state.result if state.succeeded?

        state.raise_failure!
      end

      private

      attr_reader :strategies, :budget, :pipeline, :config, :resources, :scrape_target

      def run_attempts
        AttemptState.new.tap do |state|
          strategies.each_with_index do |strategy, index|
            attempt(strategy:, next_strategy: strategies[index + 1], state:)
            break if state.succeeded? || state.aborted?
          end
        end
      end

      # rubocop:disable-next Metrics/MethodLength, Metrics/AbcSize -- hop timing + NON_FALLBACK rescue stay co-located
      def attempt(strategy:, next_strategy:, state:)
        started_ms = monotonic_ms
        request_session = pipeline.request_session_for(
          config, strategy:, resources:, scrape_url: scrape_target.effective_url
        )
        response = request_session.fetch_initial_response
        # Everything after the entry fetch leaves the next strategy its initial request slot.
        hop = Hop.new(strategy:, next_strategy:, request_session:, state:)
        budget.holding(next_strategy ? 1 : 0) { process_response(hop, response, monotonic_ms - started_ms) }
      rescue *NON_FALLBACK_ERRORS => error
        state.record_error(strategy:, error:, elapsed_ms: monotonic_ms - started_ms)
        state.abort!
      rescue Html2rss::ContractError
        raise
      rescue Html2rss::Error => error
        state.record_error(strategy:, error:, elapsed_ms: monotonic_ms - started_ms)
        log_fallback_error(strategy:, next_strategy:, error:, request_session:) if next_strategy && request_session
      end

      # rubocop:disable-next Metrics/MethodLength, Metrics/AbcSize -- extract + resolution delegate
      def process_response(hop, response, elapsed_ms)
        extraction = pipeline.extract(config:, response:, request_session: hop.request_session)
        record_extraction(hop, response, extraction, elapsed_ms)
        Log.debug("#{self.class}: strategy=#{hop.strategy} items=#{extraction.articles.size} " \
                  "host=#{response.url.host} elapsed=#{format('%.3f', budget.elapsed_seconds)}s " \
                  "budget_remaining=#{budget_remaining_label}")

        return if resolve_entry(hop, response, extraction)
        return record_success(hop, response, extraction) if extraction.articles.any?

        if DETERMINISTIC_HTTP_STATUSES.member?(response&.status)
          hop.state.abort!
          Log.debug("#{self.class}: deterministic HTTP #{response.status}; aborting auto fallback")
          return
        end

        log_info_fallback_zero_items(hop, response) if hop.next_strategy
      end

      # The one record path for an extraction, whether it came from the entry fetch or the resolved retry.
      def record_extraction(hop, response, extraction, elapsed_ms = nil)
        hop.state.remember_response(response)
        hop.state.record_items(strategy: hop.strategy, items_count: extraction.articles.size,
                               transport_meta: response.transport_meta, elapsed_ms:)
      end

      # Runs the entry-resolution tournament once per chain and retries the winner's page.
      # The hold around the strategy's work keeps the later strategy's initial request slot from the tournament.
      #
      # @return [Boolean] true when the retry extraction yielded items and ended the chain
      # rubocop:disable-next Metrics/MethodLength -- eligibility, record, retry, error policy
      def resolve_entry(hop, response, extraction)
        return false if hop.state.resolution_tried?

        return false unless (resolution = run_tournament(hop, response, extraction))

        hop.state.remember_entry_resolution(resolution)
        resolution.applied && retry_succeeded?(hop, resolution)
      rescue RequestService::RequestBudgetExceeded
        log_resolution_failure('budget_exhausted', 'entry resolution skipped (request budget exhausted)')
        false
      rescue *NON_FALLBACK_ERRORS, Html2rss::ContractError
        raise
      rescue Html2rss::Error => error
        log_resolution_failure('retry_failed', "entry resolution retry failed (#{error.class})",
                               error_class: error.class.name)
        false
      end

      def run_tournament(hop, response, extraction)
        FeedResolution.call(response:, session: hop.request_session, config:, articles: extraction.articles,
                            slots: budget.remaining_requests)
      end

      # Extracts the winner's already fetched response; the target turns sticky only when it yields items.
      def retry_succeeded?(hop, resolution)
        target = scrape_target.with_effective(resolution.scrape_url)
        extraction = extract_resolved(resolution:, strategy: hop.strategy, target:)
        record_extraction(hop, resolution.response, extraction)
        return false if extraction.articles.empty?

        record_success(hop, resolution.response, extraction, scrape_target: target)
        true
      end

      def extract_resolved(resolution:, strategy:, target:)
        retry_session = pipeline.request_session_for(config, strategy:, resources:, scrape_url: target.effective_url)
        retry_session.remember!(resolution.response.url)
        pipeline.extract(config:, response: resolution.response, request_session: retry_session)
      end

      def log_resolution_failure(event, summary, error_class: nil)
        fields = { host: Url.from_absolute(config.url).host, error_class:, message: "FeedResolution: #{summary}" }
        Log.event(:warn, "feed_resolution.#{event}", **fields.compact)
      end

      def record_success(hop, response, extraction, scrape_target: self.scrape_target)
        strategy = hop.strategy
        attempt_count = hop.state.attempts.size
        hop.state.succeed!(response:, extraction:, selected_strategy: strategy, attempt_count:, scrape_target:)
        # Extra attempts under the first strategy are its entry-resolution retry, not a fallback hop.
        log_selected(response:, strategy:, attempt_count:) unless strategy == strategies.first
      end

      def log_selected(response:, strategy:, attempt_count:)
        Log.event(
          :info, 'auto_fallback.selected',
          host: response.url.host,
          strategy: strategy.to_s,
          attempt_count:,
          message: "#{self.class}: auto selected strategy=#{strategy} after attempts=#{attempt_count} " \
                   "host=#{response.url.host} elapsed=#{format('%.3f', budget.elapsed_seconds)}s " \
                   "budget_remaining=#{budget_remaining_label}"
        )
      end

      def monotonic_ms = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)

      # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength -- shared payload then info/warn dispatch
      def log_fallback_error(strategy:, next_strategy:, error:, request_session:)
        host = request_session.url.host
        detail = "host=#{host} elapsed=#{format('%.3f', budget.elapsed_seconds)}s " \
                 "budget_remaining=#{budget_remaining_label}"
        timed_out = error.is_a?(RequestService::RequestTimedOut)
        Log.event(
          timed_out ? :info : :warn, timed_out ? 'auto_fallback.timeout' : 'auto_fallback.error',
          host:,
          strategy: strategy.to_s,
          next_strategy: next_strategy.to_s,
          error_class: error.class.name,
          message: "#{self.class}: auto fallback #{strategy} -> #{next_strategy} " \
                   "after #{timed_out ? "timeout=#{error.class}" : "error=#{error.class}"} #{detail}"
        )
        Log.debug("#{self.class}: strategy=#{strategy} error=#{error.class}: #{error.message} #{detail}")
      end

      def log_info_fallback_zero_items(hop, response)
        host = response.url.host
        Log.event(
          :info, 'auto_fallback.zero_items',
          host:, strategy: hop.strategy, next_strategy: hop.next_strategy,
          message: "#{self.class}: auto fallback #{hop.strategy} -> #{hop.next_strategy} after zero extracted items " \
                   "host=#{host} elapsed=#{format('%.3f', budget.elapsed_seconds)}s " \
                   "budget_remaining=#{budget_remaining_label}"
        )
      end

      def budget_remaining_label
        format('%.3f', budget.remaining_timeout_seconds)
      end
    end
  end
end
