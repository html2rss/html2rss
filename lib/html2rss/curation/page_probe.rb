# frozen_string_literal: true

module Html2rss
  module Curation
    ##
    # Shared page fetch and assessment for inspect and recon.
    #
    # Owns surface class, native feed hints, segment stats, and a cheap AutoSource
    # article count. Diagnostic fetch for Inspect/Recon lives on {.probe} — not twin
    # fetch helpers in those callers.
    class PageProbe # rubocop:disable Metrics/ClassLength -- one co-located fetch and assessment
      Result = Data.define(
        :requested_url,
        :final_url,
        :status,
        :scheme_downgrade,
        :alternate_feeds,
        :surface_category,
        :articles_count,
        :admission_drops,
        :segment_stats,
        :html_response,
        :content_type,
        :blocked_surface,
        :sst
      )

      ##
      # Recon facts used by Inspect and EntryResolution.
      class Result
        ##
        # @return [Hash{Symbol => Object}]
        def to_h # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- omit-empty optional keys
          {
            requested_url:,
            final_url:,
            status:,
            scheme_downgrade:,
            alternate_feeds:,
            surface_category:,
            articles_count:,
            html_response:,
            content_type:,
            **(admission_drops.any? ? { admission_drops: } : {}),
            **(segment_stats ? { segment_stats: } : {}),
            **(blocked_surface ? { blocked_surface: } : {}),
            **(sst ? { sst: } : {})
          }
        end
      end

      ##
      # Diagnostic fetch + assess bundle. One home for session build + initial GET + {call}.
      # Consumed by curation {Html2rss::Curation::Recon} and {Html2rss::Curation::Inspect}.
      Fetch = Data.define(:session, :response, :result, :strategy)

      ##
      # @param response [Html2rss::RequestService::Response]
      # @param url [String, Html2rss::Url] requested entry URL
      # @return [Result]
      def self.call(response:, url:)
        new(response:, url:).call
      end

      ##
      # Builds a request session, fetches the URL once, and runs full page recon.
      #
      # @param url [String, Html2rss::Url]
      # @param strategy [Symbol] request strategy (:auto resolves to a concrete diagnostic strategy)
      # @option options [Integer, nil] :max_redirects
      # @option options [Integer, nil] :max_requests
      # @return [Fetch]
      def self.probe(url, strategy: :auto, **)
        url_obj = Url.from_absolute(url)
        resolved = FeedPipeline::StrategyPlan.concrete_for_diagnostic(strategy)
        session = build_probe_session(url_obj, resolved, **)
        response = session.fetch_initial_response
        Fetch.new(
          session:,
          response:,
          result: call(response:, url: url_obj),
          strategy: resolved
        )
      end

      ##
      # @param url_obj [Html2rss::Url]
      # @param strategy [Symbol]
      # @option options [Integer, nil] :max_redirects
      # @option options [Integer, nil] :max_requests
      # @return [Html2rss::RequestSession]
      def self.build_probe_session(url_obj, strategy, **options) # rubocop:disable Metrics/MethodLength
        raw_config = Config::AutoSourceRequest.from_shortcut(
          url_obj.to_s, strategy:, max_redirects: options[:max_redirects], max_requests: options[:max_requests]
        ).to_config
        raw_config[:strategy] = strategy
        config = Config.from_hash(raw_config)
        resources = FeedPipeline::RuntimePolicy.resources_for(config)
        RequestSession.build(
          config:,
          strategy: config.strategy,
          budget: resources.budget,
          policy: resources.policy
        )
      end
      private_class_method :build_probe_session

      ##
      # @param sst [Html2rss::Html::SST::Document]
      # @param url [String, Html2rss::Url]
      # @param vocabulary [Html2rss::Vocabulary::Scope] the page language's scope
      # @return [Array]
      def self.discover_segments(sst, url, vocabulary:)
        link_resolver = AutoSource::Scoring::LinkResolver.new(url, vocabulary:)
        AutoSource::Segmenter.call(sst, base_url: url, strategy: :list, link_resolver:)
      end

      ##
      # @param response [Html2rss::RequestService::Response]
      # @param url [String, Html2rss::Url]
      def initialize(response:, url:)
        @response = response
        @url = url
      end

      ##
      # @return [Result]
      def call # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- assemble recon Result
        requested = Url.from_absolute(url)
        final = response.url
        parsed = response.parsed_body if response.html_response?
        vocabulary = Vocabulary[Channel.language_for(response)] if response.html_response?
        assessment = AutoSource::Assessment.call(response:, vocabulary:)
        sst_payload, segment_stats = sst_payload_and_segments(requested, vocabulary)

        Result.new(
          requested_url: requested.to_s,
          final_url: final.to_s,
          status: response.status,
          scheme_downgrade: scheme_downgrade?(requested, final),
          alternate_feeds: alternate_feeds_from(parsed),
          surface_category: assessment.surface_category,
          articles_count: refused? ? 0 : assessment.articles_count,
          admission_drops: assessment.admission_drops,
          segment_stats:,
          html_response: response.html_response?,
          content_type: response.content_type,
          blocked_surface: blocked_surface_key,
          sst: sst_payload
        )
      end

      private

      attr_reader :response, :url

      # A refused entry (401/403/429) never counts items: its body is a block page, not content.
      def refused? = RequestService::BlockedSurfaceDetected::STATUSES.member?(response.status)

      def sst_payload_and_segments(requested, vocabulary)
        return [nil, nil] unless response.html_response?

        sst = Html::SST::Normalizer.call(response.body, vocabulary:)
        return [nil, nil] unless sst

        stats = segment_stats(sst, requested, vocabulary)
        [
          { node_count: sst.node_count, degraded: sst.degraded, segment_stats: stats },
          stats
        ]
      end

      def segment_stats(sst, page_url, vocabulary)
        segments = self.class.discover_segments(sst, page_url, vocabulary:)
        return { found: 0 } if segments.empty?

        {
          found: segments.size,
          strategies: segments.map(&:strategy).uniq,
          sample_paths: segments.first(5).map { |s| s.root_node.tag_path }
        }
      end

      def scheme_downgrade?(requested, final)
        requested.scheme == 'https' && final.scheme == 'http'
      end

      def alternate_feeds_from(parsed)
        return [] unless parsed.is_a?(Nokogiri::HTML::Document)

        Html::FeedLink.from_document(parsed).map { |link| { href: link.href, mime_type: link.mime_type } }
      end

      def blocked_surface_key
        blocked = RequestService::BlockedSurface.interstitial_signature_for(response.body)
        blocked[:key].to_s if blocked
      end
    end
  end
end
