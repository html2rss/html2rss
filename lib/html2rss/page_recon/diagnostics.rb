# frozen_string_literal: true

module Html2rss
  class PageRecon
    ##
    # Diagnostic inspect path (not Capture or Recon ownership). Fetches via {.probe},
    # then adds scraper/XHR diagnostics for curation inspect surfaces.
    module Diagnostics
      ##
      # Typed diagnostic report for inspect wire payloads and Outcome policy.
      Report = Data.define(:data) do
        ##
        # @return [Boolean]
        def alternate_feeds?
          Array(data[:alternate_feeds]).any?
        end

        ##
        # @return [Integer]
        def articles_count
          data[:articles_count].to_i
        end

        ##
        # @return [Hash{Symbol => Object}]
        def to_wire_h
          data
        end
      end

      module_function

      ##
      # @param url [String]
      # @param strategy [String, Symbol]
      # @return [Report]
      def call(url:, strategy: :auto)
        probe = PageRecon.probe(url, strategy:)
        recon = probe.result
        response = probe.response

        Report.new(data: build_data(probe, recon, response))
      end

      ##
      # Runs diagnostic inspect across URLs with per-URL error isolation.
      #
      # @param urls [Enumerable<String>]
      # @param strategy [Symbol, String]
      # @param concurrency [Integer]
      # @return [Array<Report>]
      def batch(urls:, strategy: :auto, concurrency: Batch::DEFAULT_CONCURRENCY)
        Batch.map(Array(urls), concurrency:) do |url|
          call(url:, strategy:)
        rescue StandardError => error
          error_report(url, error)
        end
      end

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

      def build_data(probe, recon, response)
        data = recon.to_h.merge(
          strategy: probe.strategy,
          scraper_eligibility: scraper_info(safe_parsed_body(response))
        )
        data[:xhr_capture] = xhr_capture_info(response) if probe.strategy == :botasaurus
        data
      end
      module_function :build_data
      private_class_method :build_data

      def safe_parsed_body(response)
        return unless response.html_response?

        response.parsed_body
      rescue RequestService::UnsupportedResponseContentType
        nil
      end
      module_function :safe_parsed_body
      private_class_method :safe_parsed_body

      def error_report(url, error)
        Report.new(
          data: {
            requested_url: url.to_s,
            final_url: url.to_s,
            status: nil,
            scheme_downgrade: false,
            alternate_feeds: [],
            surface_category: :unsupported_surface,
            articles_count: 0,
            html_response: false,
            content_type: nil,
            strategy: nil,
            scraper_eligibility: { error: "#{error.class} - #{error.message}" }
          }
        )
      end
      module_function :error_report
      private_class_method :error_report
    end
  end
end
