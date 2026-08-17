# frozen_string_literal: true

module Html2rss
  module MCP
    Outcome = Data.define(:ok, :next_step, :guidance, :payload)

    ##
    # Typed MCP tool result. Owns next-step policy and guidance copy so the
    # protocol adapter does not branch on quality heuristics.
    class Outcome
      XOR_ERROR = /exactly one of config or yaml/
      NextStep = Data.define(:name, :guidance)

      ##
      # Closed set of agent next actions. Invalid names cannot be constructed.
      class NextStep
        NAMES = %i[done inspect_url validate_config apply_config scrape_url capture_config read_runtime].freeze
        GUIDANCE = {
          done: 'Done. Read payload for the result.',
          inspect_url: 'Call inspect_url next. Read payload for recon (final_url, status, ' \
                       'scheme_downgrade, alternate_feeds).',
          validate_config: 'Call validate_config with payload.yaml or a config hash (XOR, not both).',
          apply_config: 'Call apply_config next. Confirm payload.item_count before shipping.',
          scrape_url: 'Call scrape_url for articles now. strategy auto already runs Faraday then Botasaurus.',
          capture_config: 'Call capture_config for a reusable YAML draft, then follow next_step.',
          read_runtime: 'Read html2rss://runtime. Set BOTASAURUS_SCRAPER_URL on the MCP process ' \
                        'if botasaurus_configured is false.'
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
          next_step = ok ? NextStep.apply_config : NextStep.validate_config
          new(ok:, next_step:, guidance: next_step.guidance, payload: ok ? {} : { errors: })
        end

        ##
        # @param rss [String]
        # @param item_count [Integer]
        # @return [Outcome]
        def apply(rss:, item_count:)
          ok = item_count.positive?
          next_step = ok ? NextStep.done : NextStep.inspect_url
          new(ok:, next_step:, guidance: next_step.guidance, payload: { rss:, item_count: })
        end

        ##
        # @param error [Exception]
        # @param botasaurus_configured [Boolean]
        # @return [Outcome]
        def from_error(error, botasaurus_configured: false) # rubocop:disable Lint/UnusedMethodArgument -- Server always passes the runtime boolean
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
          return NextStep.done if Array(payload[:alternate_feeds]).any?
          return NextStep.capture_config if payload[:articles_count].to_i.positive?

          NextStep.scrape_url
        end

        def capture_next_step(articles_count:, has_selectors:)
          articles_count.positive? && has_selectors ? NextStep.validate_config : NextStep.inspect_url
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
