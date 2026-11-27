# frozen_string_literal: true

module Html2rss
  module MCP
    Outcome = Data.define(:ok, :next_step, :guidance, :payload)

    ##
    # Typed MCP tool result. Owns next-step policy; guidance copy lives in
    # {Playbook}.
    class Outcome # rubocop:disable Metrics/ClassLength -- next-step policy + factories stay co-located
      # Raised when an outcome is built with a wrong-typed next step or payload.
      class InvalidError < Html2rss::ContractError; end

      # Surface categories no strategy can turn into articles; the surface's own message says what to target instead.
      UNREADABLE_SURFACES = %w[unsupported_surface high_entropy_surface].freeze

      NextStep = Data.define(:name, :guidance)

      ##
      # Closed set of agent next actions. Names are owned by {Playbook::GUIDANCE}.
      class NextStep
        # Frozen name → instance table built from {Playbook::GUIDANCE}.
        ALL = Playbook::GUIDANCE.to_h { |name, guidance| [name, new(name:, guidance:)] }.freeze
        private_class_method :new

        ##
        # @param name [Symbol, String]
        # @return [NextStep]
        def self.[](name) = ALL.fetch(name.to_sym) { raise InvalidOption, "unknown next_step: #{name.inspect}" }
      end

      ##
      # @param ok [Boolean]
      # @param next_step [NextStep]
      # @param guidance [String]
      # @param payload [Hash]
      def initialize(ok:, next_step:, guidance:, payload:) # rubocop:disable Naming/MethodParameterName -- +ok+ is the envelope field
        raise InvalidError, 'next_step must be a NextStep' unless next_step.is_a?(NextStep)
        raise InvalidError, 'payload must be a Hash' unless payload.is_a?(Hash)

        super(ok: !!ok, next_step:, guidance: guidance.to_s.freeze, payload: payload.dup.freeze)
      end

      ##
      # @return [Hash{Symbol => Object}] envelope for {Contract.response}
      def to_h
        { ok:, next_step: next_step.name.to_s, guidance:, payload: }
      end

      class << self
        ##
        # @param items [Array]
        # @param requested_strategy [String, Symbol]
        # @param channel_title [String, nil]
        # @param botasaurus_configured [Boolean]
        # @option wire [String] :scrape_url required; the page the items were extracted from
        # @option wire [Hash] :admission_drops Cleanup reason counts
        # @option wire [Hash] :entry_resolution diagnostics, when entry resolution was applied
        #   or kept the entry (+no_in_scope_winner+)
        # @return [Outcome]
        def scrape(items:, requested_strategy:, channel_title:, botasaurus_configured:, **wire)
          next_step, reason = scrape_decision(items.empty?, requested_strategy, botasaurus_configured)
          new(ok: true, next_step:, guidance: Playbook.guidance(next_step, reason),
              payload: scrape_payload(items:, requested_strategy:, channel_title:, wire:))
        end

        ##
        # @param report [Curation::Inspect::Report]
        # @param botasaurus_configured [Boolean]
        # @return [Outcome]
        def inspect_report(report:, botasaurus_configured:)
          next_step, reason = inspect_decision(report, botasaurus_configured)
          new(ok: true, next_step:, guidance: Playbook.guidance(next_step, reason), payload: report.to_wire_h)
        end

        ##
        # @param result [Html2rss::Curation::Recon::Result]
        # @return [Outcome]
        def recon(result:)
          next_step = recon_next_step(result.verdict)
          guidance = Playbook.recon_guidance(result, next_step)
          new(ok: true, next_step:, guidance:, payload: result.to_h)
        end

        ##
        # @param result [Html2rss::Curation::Capture::CaptureResult]
        # @param requested_strategy [String, Symbol]
        # @return [Outcome]
        def capture(result:, requested_strategy:)
          next_step, reason = capture_decision(articles_count: result.articles_count,
                                               has_selectors: result.has_selectors, native_feed: result.native_feed)
          new(ok: true, next_step:, guidance: Playbook.guidance(next_step, reason),
              payload: capture_payload(result, requested_strategy))
        end

        ##
        # @param report [Html2rss::Config::ValidationReport]
        # @return [Outcome]
        def validate(report:)
          ok = report.success?
          next_step = ok ? NextStep[:test] : NextStep[:validate]
          payload = ok ? {} : { issues: report.issues.map(&:to_h) }
          new(ok:, next_step:, guidance: Playbook.guidance(next_step), payload:)
        end

        ##
        # @param test_result [Html2rss::Curation::Test::Result]
        # @return [Outcome]
        def test(test_result)
          next_step, reason = test_decision(test_result)
          new(
            ok: test_result.success,
            next_step:,
            guidance: test_guidance(test_result, next_step, reason),
            payload: test_result.to_h
          )
        end

        ##
        # @param batch_result [Html2rss::Curation::Batch::BatchResult]
        # @return [Outcome]
        def batch_scrape(batch_result) = batch(batch_result, NextStep[:scrape]) { |row, error| failed_row(row, error) }

        ##
        # @param batch_result [Html2rss::Curation::Batch::BatchResult]
        # @param botasaurus_configured [Boolean]
        # @return [Outcome]
        def batch_inspect(batch_result, botasaurus_configured:)
          batch(batch_result, NextStep[:inspect]) do |row, error|
            next failed_row(row, error, tool: 'inspect') if error

            report = Curation::Inspect::Report.new(data: row)
            row.merge(next_step: inspect_decision(report, botasaurus_configured).first.name.to_s)
          end
        end

        ##
        # @param batch_result [Html2rss::Curation::Batch::BatchResult]
        # @return [Outcome]
        def batch_recon(batch_result)
          batch(batch_result, NextStep[:recon]) do |row, error|
            next failed_row(row, error) if error

            row.merge(next_step: recon_next_step(Curation::Recon::Verdict[row.fetch(:verdict)]).name.to_s)
          end
        end

        ##
        # @param rss [String]
        # @param item_count [Integer]
        # @param empty [Boolean] {FeedResult#empty?} (ship gate); defaults to zero items
        # @param quality_report [Hash, nil] optional ship-quality audit summary
        # @return [Outcome]
        def apply(rss:, item_count:, empty: item_count.zero?, quality_report: nil)
          ok = !empty
          next_step, reason = ok ? [NextStep[:done]] : [NextStep[:stop], :apply_empty]
          payload = { rss:, item_count: }
          payload[:quality_report] = quality_report if quality_report
          new(ok:, next_step:, guidance: Playbook.guidance(next_step, reason), payload:)
        end

        ##
        # @param error [Exception]
        # @param url [String, nil] the single input URL of the failed tool call, when it took one
        # @param tool [String, nil] name of the tool that failed; an error never sends the agent back to that same call
        # @return [Outcome]
        def from_error(error, url: nil, tool: nil)
          next_step = next_step_for_error(error, tool)
          payload = error_payload(error, url)
          new(ok: false, next_step:, guidance: error_guidance(next_step, error, payload), payload:)
        end

        private

        # Top level: all rows ok is done, some failed says so and sends the agent to each row's next_step, none ok
        # keeps the verb's own failure step. +row_block+ decorates one row (given the row and its exception, if any).
        def batch(batch_result, failure_step)
          errors = batch_result.errors
          rows = batch_result.results.each_with_index.map { |row, index| yield(row, errors[index]) }
          step = batch_result.successful.positive? ? NextStep[:done] : failure_step
          new(ok: true, next_step: step, guidance: batch_guidance(batch_result, step),
              payload: batch_result.to_h.merge(results: rows))
        end

        def batch_guidance(batch_result, step)
          failed = batch_result.total - batch_result.successful
          return step.guidance if failed.zero? || batch_result.successful.zero?

          "#{step.guidance} #{failed} of #{batch_result.total} URLs failed: read each failed row's next_step."
        end

        # A failed row is the single-URL error envelope, flattened: same fields, same next_step as a single call
        # to +tool+ that raised it.
        def failed_row(row, error, tool: nil)
          return row unless error

          failure = from_error(error, tool:)
          row.merge(failure.payload, next_step: failure.next_step.name.to_s)
        end

        # Empty scrape: when Botasaurus is configured an auto or botasaurus run has tried every strategy, so there is
        # nothing left to call; otherwise inspect says what the page is.
        def scrape_decision(empty, requested_strategy, botasaurus_configured)
          return [NextStep[:done]] unless empty
          return [NextStep[:stop], :browser_exhausted] if botasaurus_configured && requested_strategy.to_s != 'default'

          [NextStep[:inspect]]
        end

        def scrape_payload(items:, requested_strategy:, channel_title:, wire:)
          {
            items:, total: items.size, requested_strategy: requested_strategy.to_s, channel_title:,
            scrape_url: wire.fetch(:scrape_url), **wire.slice(:entry_resolution),
            **wire.slice(:admission_drops).reject { |_, drops| drops.empty? }
          }
        end

        # Inspect never sends the agent back to scrape unless its own facts say a retry could differ: a JS shell or
        # blocked page that Botasaurus has not been tried on. Every other empty page ends in capture or stop.
        def inspect_decision(report, botasaurus_configured)
          return [NextStep[:recon]] if report.alternate_feeds?
          return [NextStep[:capture]] if report.articles_count.positive?

          empty_inspect_decision(report.data, botasaurus_configured)
        end

        def empty_inspect_decision(data, botasaurus_configured)
          return [NextStep[:stop], :not_html] unless data[:html_response]
          return browser_decision(data, botasaurus_configured) if browser_surface?(data)
          return [NextStep[:stop], :unreadable_surface] if UNREADABLE_SURFACES.include?(data[:surface_category].to_s)

          [NextStep[:capture], :static_empty]
        end

        def browser_surface?(data)
          data[:likely_js_shell] || data[:blocked_surface] || data[:surface_category].to_s == 'blocked_surface'
        end

        def browser_decision(data, botasaurus_configured)
          return [NextStep[:stop], :browser_exhausted] if data[:strategy].to_s == 'botasaurus'
          return [NextStep[:scrape], :js_shell] if botasaurus_configured

          [NextStep[:read_runtime], :browser_missing]
        end

        def recon_next_step(verdict)
          return NextStep[:done] if verdict.defer?
          return NextStep[:capture] if verdict.build?

          NextStep[:scrape]
        end

        def capture_decision(articles_count:, has_selectors:, native_feed:)
          return [NextStep[:done]] if native_feed
          return [NextStep[:test]] if articles_count.positive? && has_selectors
          return [NextStep[:scrape], :capture_scrape_only] if articles_count.positive?

          [NextStep[:stop], :capture_unusable]
        end

        def test_decision(test_result)
          return [NextStep[:apply]] if test_result.success
          return [NextStep[:validate]] if test_result.failure_kind&.schema?

          [NextStep[:stop], :test_failed]
        end

        def test_guidance(test_result, next_step, reason)
          base = if test_result.success || test_result.error_message.nil?
                   Playbook.guidance(next_step, reason)
                 else
                   "#{test_result.error_message} #{Playbook.guidance(next_step, reason)}"
                 end
          report = test_result.quality_report
          return base if report.nil? || report.warnings.empty?

          warnings = report.warnings.join(', ')
          "#{base} Review payload.quality_report warnings: #{warnings}.#{items_without_url_hint(report)}"
        end

        def items_without_url_hint(report)
          return unless report.items_without_url?

          ' Items were dropped for having no URL: fix the selectors.url selector (it must match a link on each item).'
        end

        def capture_payload(result, requested_strategy)
          {
            yaml: result.yaml, articles_count: result.articles_count, has_selectors: result.has_selectors,
            channel_title: result.channel_title, requested_strategy: requested_strategy.to_s,
            **optional_capture_fields(result)
          }
        end

        def optional_capture_fields(result)
          {
            native_feed: result.native_feed&.to_s,
            suggested_channel_url: result.suggested_channel_url&.to_s,
            segment_strategy: result.segment_strategy&.to_s,
            selected_strategy: result.selected_strategy&.to_s,
            admission_drops: (result.admission_drops if result.admission_drops.any?)
          }.compact
        end

        def error_payload(error, url)
          payload = { class: error.class.name, message: error.message }
          payload[:url] = url if url
          payload.merge!(error.diagnostics) if error.is_a?(Error)
          payload
        end

        def error_guidance(next_step, error, payload)
          case next_step.name
          when :inspect then inspect_guidance(error)
          when :stop then stop_guidance(next_step, payload)
          else next_step.guidance
          end
        end

        def stop_guidance(next_step, payload)
          retry_url = Playbook::ERROR_RETRY_URL_GUIDANCE if payload.key?(:retry_url)
          [next_step.guidance, Playbook::ERROR_STOP_GUIDANCE, retry_url].compact.join(' ')
        end

        # A timeout where every attempted strategy timed out: repeating the request is unlikely to help.
        def inspect_guidance(error)
          attempts = error.is_a?(RequestService::RequestTimedOut) ? error.attempts.to_a : []
          timed_out = attempts.any? && attempts.all? { _1[:error_class] == RequestService::RequestTimedOut.name }
          timed_out ? Playbook::ERROR_TIMEOUT_GUIDANCE : Playbook::ERROR_INSPECT_GUIDANCE
        end

        # Terminal: an internal bug, a rejected caller option, or a deterministic request policy rejection
        # that inspect would hit again.
        def terminal_error?(error)
          return true unless error.is_a?(Error)
          return true if exhausted_extraction?(error)

          [InvalidOption, *FeedPipeline::AutoFallback::NON_FALLBACK_ERRORS].any? { |klass| error.is_a?(klass) }
        end

        # An empty extraction that no strategy can read, or one where Botasaurus already ran: inspect finds nothing new.
        def exhausted_extraction?(error)
          return false unless error.is_a?(NoFeedItemsExtracted)

          UNREADABLE_SURFACES.include?(error.surface_category.to_s) ||
            error.attempts.any? { |attempt| attempt[:strategy].to_s == 'botasaurus' }
        end

        def next_step_for_error(error, tool)
          step = classified_error_step(error)
          step.name.to_s == tool && step.name != :validate ? NextStep[:stop] : step
        end

        def classified_error_step(error)
          case error
          when RequestService::BotasaurusConfigurationError then NextStep[:read_runtime]
          when Contract::UnpublishedRequestError, Contract::InvalidArgumentsError,
               ConfigArgument::ExclusiveInputError then NextStep[:validate]
          else terminal_error?(error) ? NextStep[:stop] : NextStep[:inspect]
          end
        end
      end
    end
  end
end
