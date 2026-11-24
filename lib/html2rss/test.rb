# frozen_string_literal: true

module Html2rss
  ##
  # Service that runs schema validation and live feed extraction on a configuration,
  # enforcing minimum item thresholds and capturing sample output.
  module Test # rubocop:disable Metrics/ModuleLength -- Result + FailureKind nest with owner
    FailureKind = Data.define(:name)

    ##
    # Closed failure classification for a failed test run.
    class FailureKind
      # Frozen name → instance table.
      ALL = %i[schema execution min_items quality].to_h { |name| [name, new(name:)] }.freeze
      private_class_method :new

      ##
      # @param name [Symbol, String]
      # @return [FailureKind]
      def self.[](name) = ALL.fetch(name.to_sym) { raise InvalidOption, "unknown failure kind: #{name.inspect}" }

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

    QualityReport = Data.define(:warnings, :metrics, :native_feed, :defer_reason)

    ##
    # Ship-quality audit summary for a configuration test (warn-only).
    class QualityReport
      ##
      # @param audit [Quality::Audit]
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

      ##
      # A copy carrying more warnings (each once, in order) and metrics.
      #
      # @param added_warnings [Array<Symbol>]
      # @param added_metrics [Hash{Symbol => Object}] merged over the current metrics
      # @return [QualityReport]
      def amend(added_warnings, added_metrics)
        with(warnings: (warnings + added_warnings).uniq.freeze, metrics: metrics.merge(added_metrics))
      end

      ##
      # @return [Array<Symbol>] the strict-quality thresholds the metrics breach ({Quality.failure_reasons})
      def failure_reasons = Quality.failure_reasons(metrics)

      ##
      # @return [Boolean] whether selector items were dropped for having no URL
      def items_without_url? = metrics.key?(:items_without_url)

      ##
      # @return [Hash{Symbol => Object}]
      def to_h
        {
          warnings: warnings.map(&:to_s),
          metrics:,
          **(native_feed ? { native_feed:, defer_reason: defer_reason.to_s } : {})
        }
      end
    end

    Result = Data.define(
      :success,
      :item_count,
      :sample_items,
      :items,
      :channel_title,
      :channel_url,
      :strategy_used,
      :duration_seconds,
      :validation_issues,
      :error_message,
      :failure_kind,
      :rss,
      :quality_report,
      :enhance_compare,
      :response_body
    )

    ##
    # Immutable outcome of a configuration test. Success carries +rss+ XML from the
    # first live extraction; failures carry a typed {FailureKind}.
    # +response_body+ is a copy of the fetched page for in-process readers and stays off {#to_h}.
    class Result
      ##
      # @param success [Boolean]
      # @param item_count [Integer]
      # @param sample_items [Array<Hash>]
      # @param items [Array<Hash>] up to +sample_limit+ items (title, url, published_at, description, image,
      #   categories) built from extracted articles regardless of the quality gate
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
      # @param response_body [String, nil] fetched page HTML copied from the pipeline response
      def initialize(success:, item_count:, sample_items:, channel_title:, channel_url:, # rubocop:disable Metrics/ParameterLists
                     strategy_used:, duration_seconds:, validation_issues:, error_message:,
                     failure_kind:, rss:, items: [], quality_report: nil, enhance_compare: nil, response_body: nil)
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
      # @return [Hash{Symbol => Object}] public test hash; +response_body+ stays off this wire
      def to_h # rubocop:disable Metrics/MethodLength, Metrics/AbcSize -- wire serialization omits response_body
        {
          success:,
          item_count:,
          sample_items:,
          items:,
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
    # @param sample_limit [Integer] maximum number of {Result#items} (default 3)
    # @return [Html2rss::Test::Result]
    def self.call(config_input, feed_name = nil, min_items: 1, params: {}, strategy: nil, # rubocop:disable Metrics/ParameterLists
                  strict_quality: false, compare_enhance: false, sample_limit: 3)
      raw_config, validation = Config.resolve_and_validate(config_input, feed_name:, params:)
      return validation_failure_result(validation, raw_config) unless validation.success?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      config = build_test_config(raw_config, strategy, params)
      execute_timed_pipeline(raw_config, config, started, min_items:, strict_quality:, compare_enhance:, sample_limit:)
    rescue Html2rss::ContractError
      raise
    rescue Html2rss::Error => error
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      execution_failure_result(error, raw_config, duration)
    end

    def self.build_test_config(raw_config, strategy, params)
      raw_config[:strategy] = strategy.to_sym if strategy
      raw_config[:params] = params if params&.any?
      Config.from_hash(raw_config)
    end
    private_class_method :build_test_config

    def self.execute_timed_pipeline(raw_config, config, started, min_items:, strict_quality:, # rubocop:disable Metrics/ParameterLists
                                    compare_enhance:, sample_limit:)
      feed_result, pipeline_outcome = extract_feed(raw_config)
      duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      rss_doc = feed_result.to_rss
      quality_report = Quality.report_for(rss_doc.items, channel_url: raw_config.dig(:channel, :url).to_s, config:,
                                                         feed_result:, pipeline_outcome:)
      enhance_compare = build_enhance_compare(config, pipeline_outcome) if compare_enhance

      build_test_result(raw_config, feed_result, rss_doc, duration, quality_report, enhance_compare,
                        min_items:, strict_quality:, response_body: pipeline_outcome.response.body,
                        articles: pipeline_outcome.articles, sample_limit:)
    end
    private_class_method :execute_timed_pipeline

    def self.build_test_result(raw_config, feed_result, rss_doc, duration, quality_report, enhance_compare, # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/ParameterLists
                               min_items:, strict_quality:, response_body:, articles:, sample_limit:)
      outcome = Policy.evaluate(item_count: rss_doc.items.size, min_items:, strict_quality:, quality_report:)
      strategy_used = feed_result.status.selected_strategy || raw_config[:strategy] ||
                      RequestService.default_strategy_name

      Result.new(
        success: outcome.passed,
        item_count: rss_doc.items.size,
        sample_items: extract_samples(articles),
        items: ItemSample.call(articles, limit: sample_limit),
        channel_title: feed_result.channel_title,
        channel_url: raw_config.dig(:channel, :url).to_s,
        strategy_used:,
        duration_seconds: duration.round(3),
        validation_issues: nil,
        error_message: outcome.error_message,
        failure_kind: outcome.failure_kind,
        rss: outcome.passed ? rss_doc.to_s : nil,
        quality_report:,
        enhance_compare:,
        response_body:
      )
    end
    private_class_method :build_test_result

    def self.extract_samples(articles, limit: 3)
      articles.first(limit).map do |article|
        { title: article.title.to_s.strip, url: article.url.to_s, published_at: article.published_at }
      end
    end
    private_class_method :extract_samples

    def self.extract_feed(raw_config)
      outcome, feed_result = FeedPipeline.new(raw_config).to_outcome_and_result
      [feed_result, outcome]
    end
    private_class_method :extract_feed

    def self.build_enhance_compare(config, pipeline_outcome)
      return nil unless config.selectors

      EnhanceAudit.compare(
        response: pipeline_outcome.response,
        selectors: config.selectors,
        time_zone: config.time_zone,
        vocabulary: Quality.vocabulary_for(config, pipeline_outcome)
      )
    end
    private_class_method :build_enhance_compare

    def self.validation_failure_result(report, raw_config) # rubocop:disable Metrics/MethodLength
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
        failure_kind: FailureKind[:schema],
        rss: nil,
        quality_report: nil
      )
    end
    private_class_method :validation_failure_result

    def self.execution_failure_result(error, raw_config, duration) # rubocop:disable Metrics/MethodLength
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
        failure_kind: FailureKind[:execution],
        rss: nil,
        quality_report: nil
      )
    end
    private_class_method :execution_failure_result
  end
end
