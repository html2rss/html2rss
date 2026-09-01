# frozen_string_literal: true

module Html2rss
  module MCP
    Outcome = Data.define(:ok, :next_step, :guidance, :payload)

    ##
    # Typed MCP tool result. Owns next-step policy and guidance copy so the
    # protocol adapter does not branch on quality heuristics.
    class Outcome # rubocop:disable Metrics/ClassLength -- next-step policy + factories stay co-located
      # Matches {ConfigArgument} XOR +ArgumentError+ messages.
      XOR_ERROR = /exactly one of config or yaml/
      NextStep = Data.define(:name, :guidance)

      ##
      # Closed set of agent next actions. Invalid names cannot be constructed.
      class NextStep
        # Wire names for +next_step+.
        NAMES = %i[done inspect_url validate_config apply_config scrape_url capture_config
                   read_runtime test_config].freeze
        # Default guidance copy keyed by {NAMES}.
        GUIDANCE = {
          done: 'Done. Read payload for the result.',
          inspect_url: 'Call inspect_url next. Read payload for recon (final_url, status, ' \
                       'scheme_downgrade, alternate_feeds).',
          validate_config: 'Call validate_config with payload.yaml or a config hash (XOR, not both).',
          apply_config: 'Call apply_config next. Confirm payload.item_count before shipping.',
          scrape_url: 'Call scrape_url for articles now. strategy auto already runs Faraday then Botasaurus ' \
                      'and promotes native RSS/Atom when present.',
          capture_config: 'Call capture_config for a reusable YAML draft, then follow next_step.',
          read_runtime: 'Read html2rss://runtime. Set BOTASAURUS_SCRAPER_URL on the MCP process ' \
                        'if botasaurus_configured is false.',
          test_config: 'Call test_config next (schema + live extraction). Confirm payload.item_count ' \
                       'and failure_kind before shipping.'
        }.freeze

        ##
        # @param name [Symbol, String]
        # @param guidance [String, nil]
        def initialize(name:, guidance: nil)
          step = name.to_sym
          raise ArgumentError, "unknown next_step: #{name.inspect}" unless NAMES.include?(step)

          super(name: step, guidance: (guidance || GUIDANCE.fetch(step)).freeze)
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
        # @param payload [Hash] inspect recon Hash
        # @return [Outcome]
        def inspect(payload:)
          next_step = inspect_next_step(payload)
          new(ok: true, next_step:, guidance: next_step.guidance, payload:)
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
        # @return [Outcome]
        def capture(yaml:, articles_count:, has_selectors:, channel_title:, requested_strategy:, # rubocop:disable Metrics/ParameterLists
                    segment_strategy: nil, selected_strategy: nil, admission_drops: {})
          next_step = capture_next_step(articles_count:, has_selectors:)
          new(ok: true, next_step:, guidance: next_step.guidance, payload: capture_payload(
            yaml:, articles_count:, has_selectors:, channel_title:, requested_strategy:,
            segment_strategy:, selected_strategy:, admission_drops:
          ))
        end

        ##
        # @param errors [Hash, nil] schema errors; +nil+ means success
        # @return [Outcome]
        def validate(errors:)
          ok = errors.nil?
          next_step = ok ? NextStep.test_config : NextStep.validate_config
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
        def batch_scrape(batch_result)
          next_step = batch_result.successful.positive? ? NextStep.done : NextStep.scrape_url
          new(ok: true, next_step:, guidance: next_step.guidance, payload: batch_result.to_h)
        end

        ##
        # @param batch_result [Html2rss::Batch::BatchResult]
        # @return [Outcome]
        def batch_inspect(batch_result)
          next_step = batch_result.successful.positive? ? NextStep.done : NextStep.inspect_url
          new(ok: true, next_step:, guidance: next_step.guidance, payload: batch_result.to_h)
        end

        ##
        # @param rss [String]
        # @param item_count [Integer]
        # @param empty [Boolean] {FeedResult#empty?} (ship gate); defaults to zero items
        # @return [Outcome]
        def apply(rss:, item_count:, empty: item_count.zero?)
          ok = !empty
          next_step = ok ? NextStep.done : NextStep.inspect_url
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

        def scrape_next_step(empty, botasaurus_configured:)
          return NextStep.done unless empty
          return NextStep.read_runtime unless botasaurus_configured

          NextStep.inspect_url
        end

        def scrape_payload(items:, requested_strategy:, channel_title:, admission_drops:)
          {
            items:, total: items.size, requested_strategy: requested_strategy.to_s, channel_title:,
            **(admission_drops.any? ? { admission_drops: } : {})
          }
        end

        def inspect_next_step(payload)
          # Runtime scrape_url now consumes native alternates (NativeFeed / direct feed parse).
          return NextStep.scrape_url if Array(payload[:alternate_feeds]).any?
          return NextStep.capture_config if payload[:articles_count].to_i.positive?

          NextStep.scrape_url
        end

        def capture_next_step(articles_count:, has_selectors:)
          articles_count.positive? && has_selectors ? NextStep.test_config : NextStep.inspect_url
        end

        def test_next_step(test_result)
          return NextStep.apply_config if test_result.success

          kind = test_result.failure_kind
          return NextStep.validate_config if kind&.schema?
          return NextStep.capture_config if kind&.execution? || kind&.min_items?

          NextStep.capture_config
        end

        def test_guidance(test_result, next_step)
          return next_step.guidance if test_result.success

          test_result.error_message || next_step.guidance
        end

        def capture_payload(yaml:, articles_count:, has_selectors:, channel_title:, requested_strategy:, # rubocop:disable Metrics/ParameterLists
                            segment_strategy:, selected_strategy:, admission_drops:)
          {
            yaml:, articles_count:, has_selectors:, channel_title:, requested_strategy: requested_strategy.to_s,
            **(segment_strategy ? { segment_strategy: segment_strategy.to_s } : {}),
            **(selected_strategy ? { selected_strategy: selected_strategy.to_s } : {}),
            **(admission_drops.any? ? { admission_drops: } : {})
          }
        end

        def next_step_for_error(error)
          case error
          when RequestService::BotasaurusConfigurationError then NextStep.read_runtime
          when Contract::UnpublishedRequestError then NextStep.validate_config
          when ArgumentError then argument_error_next_step(error)
          else NextStep.inspect_url
          end
        end

        def argument_error_next_step(error)
          XOR_ERROR.match?(error.message) ? NextStep.validate_config : NextStep.inspect_url
        end
      end
    end
  end
end
