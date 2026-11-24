# frozen_string_literal: true

module Html2rss
  module Test
    ##
    # Sole owner of what makes a tested feed bad: the audit metrics, the warn-only warnings, the strict-quality
    # thresholds and the failure reasons. {Test.call} and the MCP apply gate read a {QualityReport} built here;
    # {Policy} maps its {QualityReport#failure_reasons} onto pass/fail. Title junk rules stay with the admission
    # owner ({AutoSource::Cleanup.junk_reason}); {EnhanceAudit} owns the enhance metrics merged in below.
    module Quality
      # Minimum present-title length before short-title warnings.
      MIN_TITLE_LENGTH = 4

      # Audit of a feed's items: warnings and metrics (no mutation of the items).
      Audit = Data.define(:warnings, :metrics)

      ##
      # Builds the ship-quality report for rendered RSS items (shared by test and MCP apply).
      #
      # @param items [Array<RSS::Rss::Channel::Item>] the items of the one rendered document
      # @param channel_url [String]
      # @param config [Html2rss::Config]
      # @param feed_result [Html2rss::FeedResult]
      # @param pipeline_outcome [Html2rss::FeedPipeline::PipelineOutcome]
      # @param probe_native_feed [Boolean] when false, skip syndication discovery (apply ship gate);
      #   when true, discovery reads the page in +pipeline_outcome.response+ (no extra page fetch)
      # @return [QualityReport]
      def self.report_for(items, channel_url:, config:, feed_result:, pipeline_outcome:, # rubocop:disable Metrics/ParameterLists
                          probe_native_feed: true)
        native_feed = probe_native_feed_url(channel_url, config, pipeline_outcome.response)&.to_s if probe_native_feed
        report = QualityReport.from_audit(audit(items, vocabulary: vocabulary_for(config, pipeline_outcome)),
                                          native_feed:)
        report = report.amend([:url_mismatch], { url_mismatch: true }) if url_mismatch?(channel_url, feed_result)
        report = amend_items_without_url(report, pipeline_outcome)
        amend_enhance(report, config, pipeline_outcome)
      end

      ##
      # The page scope the feed itself reads, so the audit agrees with it under a +channel.language+ override.
      #
      # @param config [Html2rss::Config]
      # @param pipeline_outcome [Html2rss::FeedPipeline::PipelineOutcome]
      # @return [Vocabulary::Scope]
      def self.vocabulary_for(config, pipeline_outcome)
        Vocabulary[Channel.language_for(pipeline_outcome.response, config.channel)]
      end

      ##
      # @param items [Array<RSS::Rss::Channel::Item>]
      # @param vocabulary [Vocabulary::Scope] the scope of the page the feed was built from, so a page-only
      #   language's read-more titles count as junk like the feed's own cleanup
      # @return [Audit]
      def self.audit(items, vocabulary:)
        metrics = {
          item_count: items.size,
          unique_url_count: items.filter_map { |item| url_identity(item.link) }.uniq.size,
          **title_metrics(items.map { |item| Article::Title.collapse(item.title).to_s }.reject(&:empty?), vocabulary)
        }.freeze
        Audit.new(warnings: warnings(metrics), metrics:)
      end

      ##
      # Strict-quality failure reasons: the one threshold table.
      #
      # @param metrics [Hash{Symbol => Integer}] audit metrics
      # @return [Array<Symbol>] among +:duplicate_urls+, +:generic_titles+ (over half the items), +:short_titles+
      def self.failure_reasons(metrics)
        reasons = []
        reasons << :duplicate_urls if duplicate_urls?(metrics)
        reasons << :generic_titles if metrics.fetch(:junk_title_count) > (metrics.fetch(:item_count) / 2.0)
        reasons << :short_titles if short_titles?(metrics)
        reasons
      end

      def self.warnings(metrics)
        warnings = []
        warnings << :duplicate_urls if duplicate_urls?(metrics)
        warnings << :generic_titles if metrics.fetch(:junk_title_count).positive?
        warnings << :short_titles if short_titles?(metrics)
        warnings << :low_word_count if metrics.fetch(:low_word_count).positive?
        warnings.freeze
      end
      private_class_method :warnings

      def self.title_metrics(titles, vocabulary)
        junk, plain = titles.partition { |title| AutoSource::Cleanup.junk_reason(title, vocabulary:) }
        {
          junk_title_count: junk.size,
          short_title_count: titles.count { |title| title.length < MIN_TITLE_LENGTH },
          low_word_count: plain.count { |title| !WordCount.at_least?(title, AutoSource::Cleanup::MIN_WORDS) }
        }
      end
      private_class_method :title_metrics

      def self.duplicate_urls?(metrics) = metrics.fetch(:item_count) >= 2 && metrics.fetch(:unique_url_count) < 2
      private_class_method :duplicate_urls?

      def self.short_titles?(metrics) = metrics.fetch(:short_title_count).positive?
      private_class_method :short_titles?

      def self.url_identity(link)
        Url.from_absolute(Url.sanitize(link)).article_identity
      rescue Url::InvalidUrlError
        nil
      end
      private_class_method :url_identity

      # Selector items dropped for having no URL ({Selectors#admission_drops}) leave nothing for the audit to
      # see, so the warning names the +url+ selector as the place to look.
      def self.amend_items_without_url(report, pipeline_outcome)
        dropped = pipeline_outcome.admission_drops.fetch(Selectors::MISSING_URL_REASON, 0)
        return report if dropped.zero?

        report.amend([:items_without_url], { items_without_url: dropped })
      end
      private_class_method :amend_items_without_url

      def self.amend_enhance(report, config, pipeline_outcome)
        return report unless config.selectors&.dig(:items, :enhance)

        slice = EnhanceAudit.probe(response: pipeline_outcome.response, selectors: config.selectors,
                                   time_zone: config.time_zone, vocabulary: vocabulary_for(config, pipeline_outcome))
        return report unless slice

        report.amend(slice.warnings, { enhance_gains: slice.enhance_gains.to_h })
      end
      private_class_method :amend_enhance

      def self.url_mismatch?(channel_url, feed_result)
        status = feed_result.status
        final = status.scrape_url.to_s
        final = status.entry_url.to_s if final.empty?
        !Url.from_absolute(channel_url).same_document?(Url.from_absolute(final))
      rescue Html2rss::Url::InvalidUrlError
        false
      end
      private_class_method :url_mismatch?

      # The page the pipeline fetched (where any redirect landed) is the page probed, as in Recon and Capture: no
      # extra page fetch.
      def self.probe_native_feed_url(channel_url, config, response)
        return nil if channel_url.empty?

        resources = FeedPipeline::RuntimePolicy.resources_for(config)
        strategy = FeedPipeline::StrategyPlan.concrete_for_diagnostic(config.strategy)
        session = RequestSession.build(config:, strategy:, budget: resources.budget, policy: resources.policy)
        Syndication::Discovery.native_feed_url(response:, request_session: session)
      rescue Html2rss::ContractError
        raise
      rescue Html2rss::Error
        nil
      end
      private_class_method :probe_native_feed_url
    end
  end
end
