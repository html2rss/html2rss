# frozen_string_literal: true

module Html2rss
  ##
  # Service that runs schema validation and live feed extraction on a configuration,
  # enforcing minimum item thresholds and capturing sample output.
  module Test # rubocop:disable Metrics/ModuleLength -- Result + FailureKind nest with owner
    module_function

    ##
    # Closed failure classification for a failed test run.
    FailureKind = Data.define(:name) do
      # Closed set of test failure wire names.
      # rubocop:disable-next Lint/ConstantDefinitionInBlock -- Data.define type constant
      NAMES = Set[:schema, :execution, :min_items, :quality].freeze

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
      # @return [Boolean]
      def quality? = name == :quality

      ##
      # @return [Symbol]
      def to_sym = name

      ##
      # @return [String]
      def to_s = name.to_s
    end

    ##
    # Ship-quality audit summary for a configuration test (warn-only).
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

    ##
    # Immutable outcome of a configuration test. Success carries +rss+ XML from the
    # first live extraction; failures carry a typed {FailureKind}.
    Result = Data.define(
      :success,
      :item_count,
      :sample_items,
      :channel_title,
      :channel_url,
      :strategy_used,
      :duration_seconds,
      :validation_issues,
      :error_message,
      :failure_kind,
      :rss,
      :quality_report,
      :enhance_compare
    ) do
      ##
      # @param success [Boolean]
      # @param item_count [Integer]
      # @param sample_items [Array<Hash>]
      # @param channel_title [String, nil]
      # @param channel_url [String, nil]
      # @param strategy_used [Symbol, nil]
      # @param duration_seconds [Float]
      # @param validation_issues [Array<Html2rss::Config::ValidationIssue>, nil]
      # @param error_message [String, nil]
      # @param failure_kind [FailureKind, nil]
      # @param rss [String, nil]
      # @param quality_report [QualityReport, nil]
      # @param enhance_compare [Hash, nil]
      def initialize(success:, item_count:, sample_items:, channel_title:, channel_url:, # rubocop:disable Metrics/ParameterLists
                     strategy_used:, duration_seconds:, validation_issues:, error_message:,
                     failure_kind:, rss:, quality_report: nil, enhance_compare: nil)
        super
      end

      ##
      # @return [Boolean] whether the schema validation succeeded
      def valid_schema?
        validation_issues.nil? || validation_issues.empty?
      end

      ##
      # @return [Boolean] whether the test extracted zero items
      def empty_feed?
        item_count.zero?
      end

      ##
      # @return [Hash{Symbol => Object}] hash representation (wire shape at the serialize seam)
      def to_h # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- wire serialization of all Result fields
        {
          success:,
          item_count:,
          sample_items:,
          channel_title:,
          channel_url:,
          strategy_used:,
          duration_seconds:,
          validation_issues: validation_issues&.map(&:to_h),
          error_message:,
          failure_kind: failure_kind&.to_sym,
          rss:,
          quality_report: quality_report&.to_h,
          enhance_compare:
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
    # @param strict_quality [Boolean] when true, fail on ship-quality audit thresholds
    # @param compare_enhance [Boolean] diagnostic enhance off vs on comparison on cached HTML
    # @return [Html2rss::Test::Result]
    def call(config_input, feed_name = nil, min_items: 1, params: {}, strategy: nil, # rubocop:disable Metrics/ParameterLists
             strict_quality: false, compare_enhance: false)
      raw_config, validation = Config.resolve_and_validate(config_input, feed_name:, params:)
      return validation_failure_result(validation, raw_config) unless validation.success?

      raw_config[:strategy] = strategy.to_sym if strategy
      raw_config[:params] = params if params&.any?
      config = Config.from_hash(raw_config)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      execute_timed_pipeline(raw_config, config, started, { min_items:, strict_quality:, compare_enhance: })
    rescue StandardError => error
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      execution_failure_result(error, raw_config, duration)
    end

    def compile_quality_report(raw_config, config, feed_result, pipeline_outcome)
      quality_report_for(
        feed_result.to_rss.items,
        channel_url: raw_config.dig(:channel, :url).to_s,
        config:,
        feed_result:,
        pipeline_outcome:
      )
    end
    private_class_method :compile_quality_report

    def execute_timed_pipeline(raw_config, config, started, options)
      feed_result, pipeline_outcome = extract_feed(raw_config)
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      quality_report = compile_quality_report(raw_config, config, feed_result, pipeline_outcome)
      enhance_compare = build_enhance_compare(config, pipeline_outcome) if options[:compare_enhance]

      build_test_result(raw_config, feed_result, duration, quality_report, enhance_compare, options)
    end
    private_class_method :execute_timed_pipeline

    def evaluate_outcome(item_count, min_items, strict_quality, quality_report)
      min_items_passed = item_count >= min_items
      quality_failed = strict_quality && min_items_passed && Policy.quality_failure?(quality_report)
      passed = min_items_passed && !quality_failed
      failure_kind, error_message = Policy.outcome_failure(
        min_items_passed:, quality_failed:, item_count:, min_items:, quality_report:
      )
      log_strict_quality_failure(failure_kind, item_count) if quality_failed
      [passed, failure_kind, error_message]
    end
    private_class_method :evaluate_outcome

    def build_test_result(raw_config, feed_result, duration, quality_report, enhance_compare, options) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists
      rss_doc = feed_result.to_rss
      passed, failure_kind, error_message = evaluate_outcome(
        rss_doc.items.size, options[:min_items], options[:strict_quality], quality_report
      )
      strategy_used = feed_result.status.selected_strategy || raw_config[:strategy] ||
                      RequestService.default_strategy_name

      Result.new(
        success: passed,
        item_count: rss_doc.items.size,
        sample_items: extract_samples(rss_doc.items),
        channel_title: feed_result.channel_title,
        channel_url: raw_config.dig(:channel, :url).to_s,
        strategy_used:,
        duration_seconds: duration.round(3),
        validation_issues: nil,
        error_message:,
        failure_kind:,
        rss: passed ? rss_doc.to_s : nil,
        quality_report:,
        enhance_compare:
      )
    end
    private_class_method :build_test_result

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

    ##
    # Builds a ship-quality report for RSS items (shared by test and MCP apply).
    #
    # @param items [Array]
    # @param channel_url [String]
    # @param config [Html2rss::Config]
    # @param feed_result [Html2rss::FeedResult]
    # @param pipeline_outcome [Html2rss::FeedPipeline::PipelineOutcome]
    # @param probe_native_feed [Boolean] when false, skip syndication discovery (apply ship gate)
    # @return [QualityReport]
    def quality_report_for(items, channel_url:, config:, feed_result:, pipeline_outcome:, # rubocop:disable Metrics/ParameterLists
                           probe_native_feed: true)
      audit = AutoSource::Cleanup.audit_feed_items(items)
      native_feed = probe_native_feed ? probe_native_feed_url(channel_url, config)&.to_s : nil
      report = QualityReport.from_audit(audit, native_feed:)
      report = append_url_mismatch_warning(report, channel_url, feed_result)
      merge_enhance_audit(report, config, pipeline_outcome)
    end

    def extract_feed(raw_config)
      outcome, feed_result = FeedPipeline.new(raw_config).to_outcome_and_result
      [feed_result, outcome]
    end
    private_class_method :extract_feed

    def enhance_enabled?(config)
      return false unless config.selectors

      !!config.selectors.dig(:items, :enhance)
    end
    private_class_method :enhance_enabled?

    def build_enhance_compare(config, pipeline_outcome)
      return nil unless pipeline_outcome
      return nil unless config.selectors

      EnhanceAudit.compare(
        response: pipeline_outcome.response,
        selectors: config.selectors,
        time_zone: config.time_zone
      )
    end
    private_class_method :build_enhance_compare

    def merge_enhance_audit(report, config, pipeline_outcome) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- warning merge + metrics
      return report unless pipeline_outcome && enhance_enabled?(config)
      return report unless config.selectors

      slice = EnhanceAudit.probe(
        response: pipeline_outcome.response,
        selectors: config.selectors,
        time_zone: config.time_zone
      )
      return report unless slice

      warnings = report.warnings.dup
      slice.warnings.each { |warning| warnings << warning unless warnings.include?(warning) }
      metrics = report.metrics.merge(enhance_gains: enhance_gains_to_h(slice.enhance_gains))
      QualityReport.new(
        warnings: warnings.freeze,
        metrics:,
        native_feed: report.native_feed,
        defer_reason: report.defer_reason
      )
    end
    private_class_method :merge_enhance_audit

    def enhance_gains_to_h(enhance_gains)
      {
        items_probed: enhance_gains.items_probed,
        keys_added: enhance_gains.keys_added,
        descriptions_added: enhance_gains.descriptions_added,
        no_op: enhance_gains.no_op
      }
    end
    private_class_method :enhance_gains_to_h

    def append_url_mismatch_warning(report, channel_url, feed_result)
      return report unless url_mismatch?(channel_url, feed_result)

      warnings = report.warnings.dup
      warnings << :url_mismatch unless warnings.include?(:url_mismatch)
      QualityReport.new(
        warnings: warnings.freeze,
        metrics: report.metrics.merge(url_mismatch: true),
        native_feed: report.native_feed,
        defer_reason: report.defer_reason
      )
    end
    private_class_method :append_url_mismatch_warning

    def url_mismatch?(channel_url, feed_result)
      status = feed_result&.status
      return false unless status

      configured = channel_url.to_s
      final = status.scrape_url.to_s
      final = status.entry_url.to_s if final.empty?
      return false if configured.empty? || final.empty?

      !Url.from_absolute(configured).same_document?(Url.from_absolute(final))
    rescue ArgumentError
      false
    end
    private_class_method :url_mismatch?

    def log_strict_quality_failure(failure_kind, item_count)
      Log.info("Test strict quality: failure_kind=#{failure_kind.to_sym} item_count=#{item_count}")
    end
    private_class_method :log_strict_quality_failure

    def probe_native_feed_url(channel_url, config)
      return nil if channel_url.to_s.empty?

      resources = FeedPipeline::RuntimePolicy.resources_for(config)
      strategy = FeedPipeline::StrategyPlan.concrete_for_diagnostic(config.strategy)
      session = RequestSession.build(
        config:, strategy:, budget: resources.budget, policy: resources.policy
      )
      Syndication::Discovery.best_feed_url(page_url: channel_url, request_session: session)
    rescue StandardError
      nil
    end
    private_class_method :probe_native_feed_url

    def validation_failure_result(report, raw_config) # rubocop:disable Metrics/MethodLength
      Result.new(
        success: false,
        item_count: 0,
        sample_items: [],
        channel_title: raw_config.dig(:channel, :title),
        channel_url: raw_config.dig(:channel, :url),
        strategy_used: raw_config[:strategy],
        duration_seconds: 0.0,
        validation_issues: report.issues,
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
        validation_issues: nil,
        error_message: "#{error.class}: #{error.message}",
        failure_kind: FailureKind.coerce(:execution),
        rss: nil,
        quality_report: nil
      )
    end
    private_class_method :execution_failure_result
  end
end
