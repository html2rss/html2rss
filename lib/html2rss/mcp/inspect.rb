# frozen_string_literal: true

module Html2rss
  module MCP
    ##
    # Diagnostic inspect path (not Capture ownership). Fetches via {PageRecon.probe},
    # then adds MCP-only scraper/XHR diagnostics.
    module Inspect
      module_function

      ##
      # @param url [String]
      # @param strategy [String, Symbol]
      # @return [Hash]
      def call(url:, strategy: :auto)
        probe = PageRecon.probe(url, strategy:)
        recon = probe.result
        response = probe.response

        result = recon.to_h.merge(
          strategy: probe.strategy,
          scraper_eligibility: scraper_info(safe_parsed_body(response))
        )
        result[:xhr_capture] = xhr_capture_info(response) if probe.strategy == :botasaurus
        result
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

      def safe_parsed_body(response)
        return unless response.html_response?

        response.parsed_body
      rescue RequestService::UnsupportedResponseContentType
        nil
      end
      module_function :safe_parsed_body
      private_class_method :safe_parsed_body
    end
  end
end
