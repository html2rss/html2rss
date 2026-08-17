# frozen_string_literal: true

module Html2rss
  module MCP
    ##
    # Diagnostic inspect path (not Capture ownership). Fetches once for SST/scraper stats
    # and recon facts (final URL, status, scheme downgrade, native feed hints).
    module Inspect # rubocop:disable Metrics/ModuleLength -- diagnostic helpers stay co-located
      module_function

      ##
      # @param url [String]
      # @param strategy [String, Symbol]
      # @return [Hash]
      def call(url:, strategy: :auto) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
        resolved = FeedPipeline::StrategyPlan.concrete_for_diagnostic(strategy)
        response = fetch_response(url, resolved)
        parsed = response.parsed_body

        result = recon_fields(url, response, parsed).merge(
          strategy: resolved,
          content_type: response.content_type,
          html_response: response.html_response?,
          scraper_eligibility: scraper_info(parsed),
          sst_stats: sst_stats_from(response)
        )

        if response.html_response?
          sst = sst_document(response)
          if sst
            result[:sst] = {
              node_count: sst.node_count,
              degraded: sst.degraded,
              segment_stats: segment_stats(sst, url)
            }
          end
        end

        blocked = Html2rss::RequestService::BlockedSurface.interstitial_signature_for(response.body)
        result[:blocked_surface] = blocked[:key].to_s if blocked
        result[:xhr_capture] = xhr_capture_info(response) if resolved == :botasaurus
        merge_admission_diagnostics!(result, response)

        result
      end

      ##
      # Surfaces Cleanup admission_drops without re-running full AutoSource discovery.
      # Uses articles already extractable from a cheap AutoSource pass only when HTML.
      #
      # @param result [Hash]
      # @param response [Html2rss::RequestService::Response]
      # @return [void]
      def merge_admission_diagnostics!(result, response)
        return unless response.html_response?

        source = AutoSource.new(response, AutoSource::DEFAULT_CONFIG.merge(limit: 10))
        articles = source.articles
        result[:articles_count] = articles.size
        drops = source.admission_drops
        result[:admission_drops] = drops if drops.any?
      end
      module_function :merge_admission_diagnostics!

      ##
      # @param response [Html2rss::RequestService::Response]
      # @return [Hash] redacted XHR capture diagnostics (no query strings)
      def xhr_capture_info(response)
        captured = response.captured_responses
        {
          count: captured.size,
          sample_endpoints: captured.first(5).filter_map { |entry| redacted_endpoint(entry) },
          candidate_articles: captured.any? { |entry| xhr_candidate_articles?(entry) }
        }
      end
      module_function :xhr_capture_info

      ##
      # @param entry [Hash] captured response hash
      # @return [String, nil] scheme+host+path only
      def redacted_endpoint(entry)
        raw = entry['url'] || entry[:url]
        return unless raw

        uri = URI.parse(raw.to_s)
        return unless uri.scheme && uri.host

        "#{uri.scheme}://#{uri.host}#{uri.path}"
      rescue URI::InvalidURIError
        nil
      end
      module_function :redacted_endpoint

      ##
      # @param entry [Hash] captured response hash
      # @return [Boolean]
      def xhr_candidate_articles?(entry)
        body = entry['body'] || entry[:body]
        return false unless body.is_a?(String)

        document = JSON.parse(body, symbolize_names: true)
        AutoSource::Scraper::JsonState::CandidateDetector.candidate_array?(document)
      rescue JSON::ParserError
        false
      end
      module_function :xhr_candidate_articles?

      ##
      # @param url [String]
      # @param strategy [Symbol]
      # @return [Html2rss::RequestService::Response]
      def fetch_response(url, strategy) # rubocop:disable Metrics/MethodLength -- session construction
        raw_config = Config.auto_source_config(
          url:,
          request_controls: Config::RequestControls.from_shortcut(strategy:)
        )
        raw_config[:strategy] = strategy
        config = Config.from_hash(raw_config)
        resources = FeedPipeline::RuntimePolicy.resources_for(config)
        session = RequestSession.build(
          config:,
          strategy: config.strategy,
          budget: resources.budget,
          policy: resources.policy
        )
        session.fetch_initial_response
      end
      module_function :fetch_response

      ##
      # @param parsed [Object] parsed response body
      # @return [Array<String>, Hash]
      def scraper_info(parsed)
        return { error: 'Response is not HTML' } unless parsed.is_a?(Nokogiri::HTML::Document)

        begin
          Html2rss::AutoSource::Scraper.from(parsed).map(&:name)
        rescue Html2rss::AutoSource::Scraper::NoScraperFound => error
          { none_found: error.category.to_s }
        end
      end
      module_function :scraper_info

      ##
      # @param response [Html2rss::RequestService::Response]
      # @return [Hash, nil]
      def sst_stats_from(response)
        return nil unless response.html_response?

        doc = sst_document(response)
        return nil unless doc

        { node_count: doc.node_count, degraded: doc.degraded }
      rescue StandardError
        nil
      end
      module_function :sst_stats_from

      ##
      # @param response [Html2rss::RequestService::Response]
      # @return [Html2rss::SST::Document, nil]
      def sst_document(response)
        Html2rss::SST::Normalizer.call(response.body)
      rescue ArgumentError
        nil
      end
      module_function :sst_document

      ##
      # @param sst [Html2rss::SST::Document]
      # @param url [String]
      # @return [Hash]
      def segment_stats(sst, url)
        segments = discover_segments(sst, url)
        return { found: 0 } if segments.empty?

        {
          found: segments.size,
          strategies: segments.map(&:strategy).uniq,
          sample_paths: segments.first(5).map { |s| s.root_node.tag_path }
        }
      end
      module_function :segment_stats

      ##
      # @param sst [Html2rss::SST::Document]
      # @param url [String]
      # @return [Array]
      def discover_segments(sst, url)
        link_resolver = Scoring::LinkResolver.new(url)
        AutoSource::Segmenter.call(
          sst,
          base_url: url,
          strategy: :list,
          link_resolver:
        )
      rescue StandardError
        []
      end
      module_function :discover_segments

      ##
      # @param requested_url [String]
      # @param response [Html2rss::RequestService::Response]
      # @param parsed [Object]
      # @return [Hash]
      def recon_fields(requested_url, response, parsed)
        requested = Url.from_absolute(requested_url)
        final = response.url

        {
          requested_url: requested.to_s,
          final_url: final.to_s,
          status: response.status,
          scheme_downgrade: scheme_downgrade?(requested, final),
          alternate_feeds: alternate_feeds_from(parsed)
        }
      end
      module_function :recon_fields

      ##
      # @param requested [Html2rss::Url]
      # @param final [Html2rss::Url]
      # @return [Boolean] true when the fetch downgraded https to http
      def scheme_downgrade?(requested, final)
        requested.scheme == 'https' && final.scheme == 'http'
      end
      module_function :scheme_downgrade?

      ##
      # @param parsed [Object]
      # @return [Array<Hash{Symbol => String}>]
      def alternate_feeds_from(parsed)
        return [] unless parsed.is_a?(Nokogiri::HTML::Document)

        Html::FeedLink.from_document(parsed).map { |link| { href: link.href, mime_type: link.mime_type } }
      end
      module_function :alternate_feeds_from
    end
  end
end
