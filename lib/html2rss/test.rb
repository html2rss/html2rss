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
      :validation_errors,
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
      # @param validation_errors [Hash, nil]
      # @param error_message [String, nil]
      # @param failure_kind [FailureKind, nil]
      # @param rss [String, nil]
      # @param quality_report [QualityReport, nil]
      # @param enhance_compare [Hash, nil]
      def initialize(success:, item_count:, sample_items:, channel_title:, channel_url:, # rubocop:disable Metrics/ParameterLists
                     strategy_used:, duration_seconds:, validation_errors:, error_message:,
                     failure_kind:, rss:, quality_report: nil, enhance_compare: nil)
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
    def call(config_input, feed_name = nil, min_items: 1, params: {}, strategy: nil, # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength, Metrics/AbcSize, Metrics/PerceivedComplexity, Metrics/CyclomaticComplexity
             strict_quality: false, compare_enhance: false)
      raw_config, validation = Config.resolve_and_validate(config_input, feed_name:, params:)
      return validation_failure_result(validation.errors.to_h, raw_config) unless validation.success?

      raw_config[:strategy] = strategy.to_sym if strategy
      raw_config[:params] = params if params&.any?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        feed_result, pipeline_outcome = extract_feed(raw_config, compare_enhance:)
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

        rss_doc = feed_result.to_rss
        rss_xml = rss_doc.to_s
        item_count = rss_doc.items.size
        sample_items = extract_samples(rss_doc.items)
        quality_report = build_quality_report(
          rss_doc.items,
          channel_url: raw_config.dig(:channel, :url).to_s,
          raw_config:,
          feed_result:,
          pipeline_outcome:
        )
        enhance_compare = build_enhance_compare(raw_config, pipeline_outcome) if compare_enhance

        channel_title = feed_result.channel_title
        channel_url = raw_config.dig(:channel, :url).to_s
        strategy_used = feed_result.status.selected_strategy || raw_config[:strategy] || :faraday
        min_items_passed = item_count >= min_items
        quality_failed = strict_quality && min_items_passed && quality_failure?(quality_report)
        passed = min_items_passed && !quality_failed
        failure_kind, error_message = outcome_failure(min_items_passed:, quality_failed:, item_count:, min_items:,
                                                      quality_report:)

        log_strict_quality_failure(failure_kind, item_count) if quality_failed

        Result.new(
          success: passed,
          item_count:,
          sample_items:,
          channel_title:,
          channel_url:,
          strategy_used:,
          duration_seconds: duration.round(3),
          validation_errors: nil,
          error_message:,
          failure_kind:,
          rss: passed ? rss_xml : nil,
          quality_report:,
          enhance_compare:
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

    ##
    # Builds a ship-quality report for RSS items (shared by test and MCP apply).
    #
    # @param items [Array]
    # @param channel_url [String]
    # @param raw_config [Hash]
    # @param feed_result [Html2rss::FeedResult]
    # @param pipeline_outcome [Html2rss::FeedPipeline::PipelineOutcome, nil]
    # @param probe_native_feed [Boolean] when false, skip syndication discovery (apply ship gate)
    # @return [QualityReport]
    def quality_report_for(items, channel_url:, raw_config:, feed_result:, pipeline_outcome: nil, # rubocop:disable Metrics/ParameterLists
                           probe_native_feed: true)
      build_quality_report(
        items,
        channel_url:,
        raw_config:,
        feed_result:,
        pipeline_outcome:,
        probe_native_feed:
      )
    end

    def extract_feed(raw_config, compare_enhance:)
      if enhance_audit_needed?(raw_config, compare_enhance:)
        outcome, feed_result = FeedPipeline.new(raw_config).to_outcome_and_result
        [feed_result, outcome]
      else
        [Html2rss.feed_result(raw_config), nil]
      end
    end
    private_class_method :extract_feed

    def enhance_audit_needed?(raw_config, compare_enhance:)
      compare_enhance || enhance_enabled?(raw_config)
    end
    private_class_method :enhance_audit_needed?

    def enhance_enabled?(raw_config)
      config = Config.from_hash(raw_config)
      return false unless config.selectors

      !!config.selectors.dig(:items, :enhance)
    end
    private_class_method :enhance_enabled?

    def build_enhance_compare(raw_config, pipeline_outcome)
      return nil unless pipeline_outcome

      config = Config.from_hash(raw_config)
      return nil unless config.selectors

      EnhanceAudit.compare(
        response: pipeline_outcome.response,
        selectors: config.selectors,
        time_zone: config.time_zone
      )
    end
    private_class_method :build_enhance_compare

    def build_quality_report(items, channel_url:, raw_config:, feed_result:, pipeline_outcome: nil, # rubocop:disable Metrics/ParameterLists
                             probe_native_feed: true)
      audit = AutoSource::Cleanup.audit_feed_items(items)
      native_feed = probe_native_feed ? probe_native_feed_url(channel_url, raw_config)&.to_s : nil
      report = QualityReport.from_audit(audit, native_feed:)
      report = append_url_mismatch_warning(report, channel_url, feed_result)
      merge_enhance_audit(report, raw_config, pipeline_outcome)
    end
    private_class_method :build_quality_report

    def merge_enhance_audit(report, raw_config, pipeline_outcome) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- warning merge + metrics
      return report unless pipeline_outcome && enhance_enabled?(raw_config)

      config = Config.from_hash(raw_config)
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

    def quality_failure?(quality_report)
      metrics = quality_report.metrics
      item_count = metrics[:item_count]
      return false if item_count.zero?

      duplicate_urls_failure?(metrics) || junk_title_ratio_failure?(metrics) || short_title_failure?(metrics)
    end
    private_class_method :quality_failure?

    def duplicate_urls_failure?(metrics)
      metrics[:item_count] >= 2 && metrics[:unique_url_count] < 2
    end
    private_class_method :duplicate_urls_failure?

    def junk_title_ratio_failure?(metrics)
      metrics[:junk_title_count] > (metrics[:item_count] / 2.0)
    end
    private_class_method :junk_title_ratio_failure?

    def short_title_failure?(metrics)
      metrics[:short_title_count].positive?
    end
    private_class_method :short_title_failure?

    def outcome_failure(min_items_passed:, quality_failed:, item_count:, min_items:, quality_report:)
      return [nil, nil] if min_items_passed && !quality_failed
      unless min_items_passed
        return [FailureKind.coerce(:min_items),
                "Extracted #{item_count} items (minimum required: #{min_items})"]
      end

      [FailureKind.coerce(:quality), quality_failure_message(quality_report)]
    end
    private_class_method :outcome_failure

    def quality_failure_message(quality_report)
      reasons = quality_failure_reasons(quality_report.metrics)
      "Feed quality check failed (#{reasons.join(', ')})"
    end
    private_class_method :quality_failure_message

    def quality_failure_reasons(metrics)
      reasons = []
      reasons << 'duplicate_urls' if duplicate_urls_failure?(metrics)
      reasons << 'generic_titles' if junk_title_ratio_failure?(metrics)
      reasons << 'short_titles' if short_title_failure?(metrics)
      reasons
    end
    private_class_method :quality_failure_reasons

    def log_strict_quality_failure(failure_kind, item_count)
      Log.info("Test strict quality: failure_kind=#{failure_kind.to_sym} item_count=#{item_count}")
    end
    private_class_method :log_strict_quality_failure

    def probe_native_feed_url(channel_url, raw_config)
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
    private_class_method :probe_native_feed_url

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
