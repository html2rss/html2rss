# frozen_string_literal: true

module Html2rss
  ##
  # Service that runs schema validation and live feed extraction on a configuration,
  # enforcing minimum item thresholds and capturing sample output.
  module Test # rubocop:disable Metrics/ModuleLength -- Result + FailureKind nest with owner
    module_function

    FailureKind = Data.define(:name)

    ##
    # Closed failure classification for a failed test run.
    class FailureKind
      # Closed set of test failure wire names.
      NAMES = Set[:schema, :execution, :min_items].freeze

      class << self
        ##
        # @param value [FailureKind, Symbol, String]
        # @return [FailureKind]
        def coerce(value)
          return value if value.is_a?(self)

          new(name: value.to_sym)
        end
      end

      ##
      # @param name [Symbol]
      def initialize(name:)
        raise ArgumentError, "unknown failure kind: #{name.inspect}" unless NAMES.include?(name)

        super
      end

      ##
      # @return [Boolean]
      def schema? = name == :schema

      ##
      # @return [Boolean]
      def execution? = name == :execution

      ##
      # @return [Boolean]
      def min_items? = name == :min_items

      ##
      # @return [Symbol]
      def to_sym = name

      ##
      # @return [String]
      def to_s = name.to_s
    end

    ##
    # Immutable outcome of a configuration test. Success carries +rss+ XML from the
    # first live extraction; failures carry a typed {FailureKind}.
    QualityReport = Data.define(:warnings, :metrics, :native_feed, :defer_reason) do
      ##
      # @return [Hash{Symbol => Object}]
      def to_h
        {
          warnings: warnings.map(&:to_s),
          metrics:,
          **(native_feed ? { native_feed:, defer_reason: defer_reason.to_s } : {})
        }.compact
      end

      ##
      # @param audit [Html2rss::AutoSource::Cleanup::AuditResult]
      # @param native_feed [String, nil]
      # @return [QualityReport]
      def self.from_audit(audit, native_feed: nil)
        report_warnings = audit.warnings.dup
        defer_reason = nil
        if native_feed
          report_warnings << :native_feed_present unless report_warnings.include?(:native_feed_present)
          defer_reason = :native_feed
        end
        new(warnings: report_warnings.freeze, metrics: audit.metrics, native_feed:, defer_reason:)
      end
    end

    Result = Data.define(
      :success,
      :item_count,
      :sample_items,
      :channel_title,
      :channel_url,
      :strategy_used,
      :duration_seconds,
      :validation_errors,
      :error_message,
      :failure_kind,
      :rss,
      :quality_report
    ) do
      def initialize(success:, item_count:, sample_items:, channel_title:, channel_url:, # rubocop:disable Metrics/ParameterLists
                     strategy_used:, duration_seconds:, validation_errors:, error_message:,
                     failure_kind:, rss:, quality_report: nil)
        super
      end

      ##
      # @return [Boolean] whether the schema validation succeeded
      def valid_schema?
        validation_errors.nil? || validation_errors.empty?
      end

      ##
      # @return [Boolean] whether the test extracted zero items
      def empty_feed?
        item_count.zero?
      end

      ##
      # @return [Hash{Symbol => Object}] hash representation
      def to_h # rubocop:disable Metrics/MethodLength
        {
          success:,
          item_count:,
          sample_items:,
          channel_title:,
          channel_url:,
          strategy_used:,
          duration_seconds:,
          validation_errors:,
          error_message:,
          failure_kind: failure_kind&.to_sym,
          rss:,
          quality_report: quality_report&.to_h
        }.compact
      end
    end

    ##
    # Tests a configuration by validating schema and executing live feed extraction.
    #
    # @param config_input [Hash, String] config hash, YAML string, or file path
    # @param feed_name [String, nil] optional feed name for multi-feed files
    # @param min_items [Integer] minimum extracted items required to pass
    # @param params [Hash] optional dynamic feed parameters
    # @param strategy [Symbol, nil] optional strategy override
    # @return [Html2rss::Test::Result]
    def call(config_input, feed_name = nil, min_items: 1, params: {}, strategy: nil) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
      raw_config, validation = Config.resolve_and_validate(config_input, feed_name:, params:)
      return validation_failure_result(validation.errors.to_h, raw_config) unless validation.success?

      raw_config[:strategy] = strategy.to_sym if strategy
      raw_config[:params] = params if params&.any?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        feed_result = Html2rss.feed_result(raw_config)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        rss_doc = feed_result.to_rss
        rss_xml = rss_doc.to_s
        item_count = rss_doc.items.size
        sample_items = extract_samples(rss_doc.items)
        quality_report = build_quality_report(
          rss_doc.items,
          channel_url: raw_config.dig(:channel, :url).to_s,
          raw_config:
        )

        channel_title = feed_result.channel_title
        channel_url = raw_config.dig(:channel, :url).to_s
        strategy_used = feed_result.status.selected_strategy || raw_config[:strategy] || :faraday
        passed = item_count >= min_items

        Result.new(
          success: passed,
          item_count:,
          sample_items:,
          channel_title:,
          channel_url:,
          strategy_used:,
          duration_seconds: duration.round(3),
          validation_errors: nil,
          error_message: passed ? nil : "Extracted #{item_count} items (minimum required: #{min_items})",
          failure_kind: passed ? nil : FailureKind.coerce(:min_items),
          rss: passed ? rss_xml : nil,
          quality_report:
        )
      rescue StandardError => error
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        execution_failure_result(error, raw_config, duration)
      end
    end

    def extract_samples(items, limit: 3)
      items.first(limit).map do |item|
        {
          title: item.title.to_s.strip,
          url: (item.respond_to?(:link) ? item.link : item.url).to_s,
          published_at: (item.respond_to?(:pubDate) ? item.pubDate : item.published_at)
        }
      end
    end
    private_class_method :extract_samples

    def build_quality_report(items, channel_url:, raw_config:)
      audit = AutoSource::Cleanup.audit_feed_items(items)
      native_feed = probe_native_feed(channel_url, raw_config)&.to_s
      QualityReport.from_audit(audit, native_feed:)
    end
    private_class_method :build_quality_report

    def probe_native_feed(channel_url, raw_config)
      return nil if channel_url.to_s.empty?

      config = Config.from_hash(raw_config)
      resources = FeedPipeline::RuntimePolicy.resources_for(config)
      strategy = FeedPipeline::StrategyPlan.concrete_for_diagnostic(raw_config[:strategy])
      session = RequestSession.build(
        config:, strategy:, budget: resources.budget, policy: resources.policy
      )
      Syndication::Discovery.best_feed_url(page_url: channel_url, request_session: session)
    rescue StandardError
      nil
    end
    private_class_method :probe_native_feed

    def validation_failure_result(errors, raw_config) # rubocop:disable Metrics/MethodLength
      Result.new(
        success: false,
        item_count: 0,
        sample_items: [],
        channel_title: raw_config.dig(:channel, :title),
        channel_url: raw_config.dig(:channel, :url),
        strategy_used: raw_config[:strategy],
        duration_seconds: 0.0,
        validation_errors: errors,
        error_message: 'Configuration schema validation failed',
        failure_kind: FailureKind.coerce(:schema),
        rss: nil,
        quality_report: nil
      )
    end
    private_class_method :validation_failure_result

    def execution_failure_result(error, raw_config, duration) # rubocop:disable Metrics/MethodLength
      Result.new(
        success: false,
        item_count: 0,
        sample_items: [],
        channel_title: raw_config.dig(:channel, :title),
        channel_url: raw_config.dig(:channel, :url),
        strategy_used: raw_config[:strategy],
        duration_seconds: duration.round(3),
        validation_errors: nil,
        error_message: "#{error.class}: #{error.message}",
        failure_kind: FailureKind.coerce(:execution),
        rss: nil,
        quality_report: nil
      )
    end
    private_class_method :execution_failure_result
  end
end
