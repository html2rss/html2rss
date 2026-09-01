# frozen_string_literal: true

module Html2rss
  module MCP
    Outcome = Data.define(:ok, :next_step, :guidance, :payload)

    ##
    # Typed MCP tool result. Owns next-step policy; guidance copy lives in
    # {Playbook}.
    class Outcome # rubocop:disable Metrics/ClassLength -- next-step policy + factories stay co-located
      # Matches {ConfigArgument} XOR +ArgumentError+ messages.
      XOR_ERROR = /exactly one of config or yaml/
      NextStep = Data.define(:name, :guidance)

      ##
      # Closed set of agent next actions. Invalid names cannot be constructed.
      class NextStep
        # Wire names for +next_step+.
        NAMES = %i[done inspect recon validate apply scrape capture read_runtime test].freeze

        ##
        # @param name [Symbol, String]
        # @param guidance [String, nil]
        def initialize(name:, guidance: nil)
          step = name.to_sym
          raise ArgumentError, "unknown next_step: #{name.inspect}" unless NAMES.include?(step)

          super(name: step, guidance: (guidance || Playbook::GUIDANCE.fetch(step)).freeze)
        end

        class << self
          NAMES.each { |step| define_method(step) { new(name: step) } }
        end
      end

      ##
      # @param ok [Boolean]
      # @param next_step [NextStep]
      # @param guidance [String]
      # @param payload [Hash]
      def initialize(ok:, next_step:, guidance:, payload:) # rubocop:disable Naming/MethodParameterName -- +ok+ is the envelope field
        raise ArgumentError, 'next_step must be a NextStep' unless next_step.is_a?(NextStep)
        raise ArgumentError, 'payload must be a Hash' unless payload.is_a?(Hash)

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
        # @param admission_drops [Hash]
        # @param botasaurus_configured [Boolean]
        # @return [Outcome]
        def scrape(items:, requested_strategy:, channel_title:, botasaurus_configured:, admission_drops: {})
          next_step = scrape_next_step(items.empty?, botasaurus_configured:)
          new(ok: true, next_step:, guidance: next_step.guidance,
              payload: scrape_payload(items:, requested_strategy:, channel_title:, admission_drops:))
        end

        ##
        # @param report [PageRecon::Diagnostics::Report]
        # @return [Outcome]
        def inspect(report:)
          next_step = inspect_next_step(report)
          new(ok: true, next_step:, guidance: next_step.guidance, payload: report.to_wire_h)
        end

        ##
        # @param result [Html2rss::Recon::Result]
        # @return [Outcome]
        def recon(result:)
          next_step = recon_next_step(result)
          new(ok: true, next_step:, guidance: next_step.guidance, payload: result.to_h)
        end

        ##
        # @param yaml [String]
        # @param articles_count [Integer]
        # @param has_selectors [Boolean]
        # @param channel_title [String, nil]
        # @param requested_strategy [String, Symbol]
        # @param segment_strategy [Symbol, String, nil]
        # @param selected_strategy [Symbol, String, nil]
        # @param admission_drops [Hash]
        # @param native_feed [String, nil]
        # @return [Outcome]
        def capture(yaml:, articles_count:, has_selectors:, channel_title:, requested_strategy:, # rubocop:disable Metrics/ParameterLists
                    segment_strategy: nil, selected_strategy: nil, admission_drops: {}, native_feed: nil)
          next_step = capture_next_step(articles_count:, has_selectors:, native_feed:)
          new(ok: true, next_step:, guidance: next_step.guidance, payload: capture_payload(
            yaml:, articles_count:, has_selectors:, channel_title:, requested_strategy:,
            segment_strategy:, selected_strategy:, admission_drops:, native_feed:
          ))
        end

        ##
        # @param errors [Hash, nil] schema errors; +nil+ means success
        # @return [Outcome]
        def validate(errors:)
          ok = errors.nil?
          next_step = ok ? NextStep.test : NextStep.validate
          new(ok:, next_step:, guidance: next_step.guidance, payload: ok ? {} : { errors: })
        end

        ##
        # @param test_result [Html2rss::Test::Result]
        # @return [Outcome]
        def test(test_result)
          next_step = test_next_step(test_result)
          new(
            ok: test_result.success,
            next_step:,
            guidance: test_guidance(test_result, next_step),
            payload: test_result.to_h
          )
        end

        ##
        # @param batch_result [Html2rss::Batch::BatchResult]
        # @return [Outcome]
        def batch_scrape(batch_result) = batch(batch_result, NextStep.scrape)

        ##
        # @param batch_result [Html2rss::Batch::BatchResult]
        # @return [Outcome]
        def batch_inspect(batch_result) = batch(batch_result, NextStep.inspect)

        ##
        # @param batch_result [Html2rss::Batch::BatchResult]
        # @return [Outcome]
        def batch_recon(batch_result) = batch(batch_result, NextStep.recon)

        ##
        # @param rss [String]
        # @param item_count [Integer]
        # @param empty [Boolean] {FeedResult#empty?} (ship gate); defaults to zero items
        # @return [Outcome]
        def apply(rss:, item_count:, empty: item_count.zero?)
          ok = !empty
          next_step = ok ? NextStep.done : NextStep.inspect
          new(ok:, next_step:, guidance: next_step.guidance, payload: { rss:, item_count: })
        end

        ##
        # @param error [Exception]
        # @return [Outcome]
        def from_error(error)
          next_step = next_step_for_error(error)
          new(ok: false, next_step:, guidance: next_step.guidance,
              payload: { class: error.class.name, message: error.message })
        end

        private

        def batch(batch_result, failure_step)
          step = batch_result.successful.positive? ? NextStep.done : failure_step
          new(ok: true, next_step: step, guidance: step.guidance, payload: batch_result.to_h)
        end

        def scrape_next_step(empty, botasaurus_configured:)
          return NextStep.done unless empty
          return NextStep.read_runtime unless botasaurus_configured

          NextStep.inspect
        end

        def scrape_payload(items:, requested_strategy:, channel_title:, admission_drops:)
          {
            items:, total: items.size, requested_strategy: requested_strategy.to_s, channel_title:,
            **(admission_drops.any? ? { admission_drops: } : {})
          }
        end

        def inspect_next_step(report)
          return NextStep.recon if report.alternate_feeds?
          return NextStep.capture if report.articles_count.positive?

          NextStep.scrape
        end

        def recon_next_step(result)
          return NextStep.done if result.defer?
          return NextStep.capture if result.build?

          NextStep.scrape
        end

        def capture_next_step(articles_count:, has_selectors:, native_feed: nil)
          return NextStep.done if native_feed

          articles_count.positive? && has_selectors ? NextStep.test : NextStep.inspect
        end

        def test_next_step(test_result)
          return NextStep.apply if test_result.success

          kind = test_result.failure_kind
          return NextStep.validate if kind&.schema?
          return NextStep.capture if kind&.execution? || kind&.min_items?

          NextStep.capture
        end

        def test_guidance(test_result, next_step)
          base = if test_result.success
                   next_step.guidance
                 else
                   test_result.error_message || next_step.guidance
                 end
          warnings = test_result.quality_report&.warnings
          return base if warnings.nil? || warnings.empty?

          "#{base} Review payload.quality_report warnings: #{warnings.join(', ')}."
        end

        def capture_payload(yaml:, articles_count:, has_selectors:, channel_title:, requested_strategy:, # rubocop:disable Metrics/ParameterLists
                            segment_strategy:, selected_strategy:, admission_drops:, native_feed: nil)
          {
            yaml:, articles_count:, has_selectors:, channel_title:, requested_strategy: requested_strategy.to_s,
            **(native_feed ? { native_feed: native_feed.to_s } : {}),
            **(segment_strategy ? { segment_strategy: segment_strategy.to_s } : {}),
            **(selected_strategy ? { selected_strategy: selected_strategy.to_s } : {}),
            **(admission_drops.any? ? { admission_drops: } : {})
          }
        end

        def next_step_for_error(error)
          case error
          when RequestService::BotasaurusConfigurationError then NextStep.read_runtime
          when Contract::UnpublishedRequestError then NextStep.validate
          when ArgumentError then argument_error_next_step(error)
          else NextStep.inspect
          end
        end

        def argument_error_next_step(error)
          XOR_ERROR.match?(error.message) ? NextStep.validate : NextStep.inspect
        end
      end
    end
  end
end
