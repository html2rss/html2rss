# frozen_string_literal: true

module Html2rss
  ##
  # Shared page recon for MCP Inspect, curation Recon, and FeedResolution probes.
  #
  # Owns surface class, native feed hints, segment stats, and a cheap AutoSource
  # article count. Diagnostic fetch for Inspect/Recon lives on {.probe} — not twin
  # fetch helpers in those callers.
  class PageRecon # rubocop:disable Metrics/ClassLength -- recon bag stays co-located
    ##
    # Cheap surface + admission facts shared by AutoFallback gates and FeedResolution probes.
    Assessment = Data.define(:surface_category, :articles_count, :admission_drops, :html_response) do
      ##
      # @return [Html2rss::SurfaceCategory]
      def category = SurfaceCategory.coerce(surface_category)

      ##
      # @return [Boolean]
      def weak? = category.weak?

      ##
      # @return [Boolean]
      def blocked? = category.blocked?

      ##
      # @return [Boolean]
      def listing_bonus? = category.listing_bonus?
    end
    ##
    # Recon facts used by Inspect and FeedResolution.
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
    ) do
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
    # Consumed by curation {Html2rss::Recon} and MCP {Html2rss::MCP::Inspect}.
    Probe = Data.define(:session, :response, :result, :strategy)

    ##
    # @param response [Html2rss::RequestService::Response]
    # @param url [String, Html2rss::Url] requested entry URL
    # @param strategy [Symbol, nil] unused (reserved for callers that already chose a strategy)
    # @return [Result]
    def self.call(response:, url:, strategy: nil) # rubocop:disable Lint/UnusedMethodArgument
      new(response:, url:).call
    end

    ##
    # Builds a request session, fetches the URL once, and runs full page recon.
    #
    # @param url [String, Html2rss::Url]
    # @param strategy [Symbol] request strategy (:auto resolves to a concrete diagnostic strategy)
    # @option options [Integer, nil] :max_redirects
    # @option options [Integer, nil] :max_requests
    # @return [Probe]
    def self.probe(url, strategy: :auto, **)
      url_obj = Url.from_absolute(url)
      resolved = FeedPipeline::StrategyPlan.concrete_for_diagnostic(strategy)
      session = build_probe_session(url_obj, resolved, **)
      response = session.fetch_initial_response
      Probe.new(
        session:,
        response:,
        result: call(response:, url: url_obj, strategy: resolved),
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
      raw_config = Config.auto_source_config(
        url: url_obj.to_s,
        request_controls: Config::RequestControls.from_shortcut(
          strategy:,
          max_redirects: options[:max_redirects],
          max_requests: options[:max_requests]
        )
      )
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
    # Cheap page assessment for policy gates and probe scoring (fixed AutoSource limit).
    #
    # @param response [Html2rss::RequestService::Response]
    # @param url [String, Html2rss::Url]
    # @return [Assessment]
    def self.assess(response:, url:)
      new(response:, url:).assess
    end

    ##
    # Surface class only — no AutoSource extract (for empty-extract error labels).
    #
    # @param response [Html2rss::RequestService::Response]
    # @param url [String, Html2rss::Url]
    # @return [Symbol]
    def self.surface_category_for(response:, url:)
      new(response:, url:).surface_category_for
    end

    ##
    # @param sst [Html2rss::SST::Document]
    # @param url [String, Html2rss::Url]
    # @return [Array]
    def self.discover_segments(sst, url)
      link_resolver = Scoring::LinkResolver.new(url)
      AutoSource::Segmenter.call(sst, base_url: url, strategy: :list, link_resolver:)
    rescue StandardError
      []
    end

    ##
    # @param response [Html2rss::RequestService::Response]
    # @param url [String, Html2rss::Url]
    def initialize(response:, url:)
      @response = response
      @url = url
    end

    ##
    # @return [Assessment]
    def assess
      return feed_assessment if response.feed_response?

      parsed = html_parsed_body
      articles_count, admission_drops = cheap_articles
      Assessment.new(
        surface_category: surface_category(parsed),
        articles_count:,
        admission_drops:,
        html_response: true
      )
    end

    ##
    # @return [Symbol]
    def surface_category_for
      return :unsupported_surface if response.feed_response?

      surface_category(html_parsed_body)
    end

    ##
    # @return [Result]
    def call # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- assemble recon Result
      requested = Url.from_absolute(url)
      final = response.url
      parsed = html_parsed_body
      assessment = assess
      sst_payload, segment_stats = sst_payload_and_segments(requested)

      Result.new(
        requested_url: requested.to_s,
        final_url: final.to_s,
        status: response.status,
        scheme_downgrade: scheme_downgrade?(requested, final),
        alternate_feeds: alternate_feeds_from(parsed),
        surface_category: assessment.surface_category,
        articles_count: assessment.articles_count,
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

    def feed_assessment
      Assessment.new(
        surface_category: :unsupported_surface,
        articles_count: 0,
        admission_drops: {},
        html_response: false
      )
    end

    def html_parsed_body
      return unless response.html_response?

      response.parsed_body
    rescue RequestService::UnsupportedResponseContentType
      nil
    end

    def surface_category(parsed)
      return :unsupported_surface unless parsed

      AutoSource::Scraper.classify_no_scraper_surface(parsed, body: response.body)
    end

    def cheap_articles
      return [0, {}] unless response.html_response?

      source = AutoSource.new(response, AutoSource::DEFAULT_CONFIG.merge(limit: 10))
      [source.articles.size, source.admission_drops]
    end

    def sst_payload_and_segments(requested)
      return [nil, nil] unless response.html_response?

      sst = sst_document
      return [nil, nil] unless sst

      stats = segment_stats(sst, requested)
      [
        { node_count: sst.node_count, degraded: sst.degraded, segment_stats: stats },
        stats
      ]
    end

    def sst_document
      Html2rss::SST::Normalizer.call(response.body)
    rescue ArgumentError
      nil
    end

    def segment_stats(sst, page_url)
      segments = self.class.discover_segments(sst, page_url)
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
