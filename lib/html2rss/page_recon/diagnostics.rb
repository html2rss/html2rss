# frozen_string_literal: true

module Html2rss
  class PageRecon
    ##
    # Diagnostic inspect path (not Capture or Recon ownership). Fetches via {.probe},
    # then adds scraper/XHR diagnostics for curation inspect surfaces.
    module Diagnostics # rubocop:disable Metrics/ModuleLength -- diagnostic wire fields stay co-located
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

      # Minimum HTML body size to treat zero-article weak surfaces as likely JS shells.
      JS_SHELL_MIN_BODY_BYTES = 8_192
      private_constant :JS_SHELL_MIN_BODY_BYTES

      module_function

      ##
      # @param url [String]
      # @param strategy [String, Symbol]
      # @param deep [Boolean] when true and strategy is auto, one Botasaurus hop if configured
      # @return [Report]
      def call(url:, strategy: :auto, deep: false)
        probe = PageRecon.probe(url, strategy: resolve_inspect_strategy(strategy, deep:))
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
        return { error: 'Response is not HTML' } unless Html::Document.html_document?(parsed)

        begin
          Html2rss::AutoSource::Scraper.from(parsed).map(&:name)
        rescue Html2rss::AutoSource::Scraper::NoScraperFound => error
          { none_found: error.category.to_s }
        end
      end

      def build_data(probe, recon, response)
        data = recon.to_h.merge(
          strategy: probe.strategy,
          scraper_eligibility: scraper_info(safe_parsed_body(response)),
          html_present: html_present?(recon, response),
          likely_js_shell: likely_js_shell?(recon, response),
          redirect_summary: redirect_summary(recon)
        )
        data[:xhr_capture] = xhr_capture_info(response) if probe.strategy == :botasaurus
        log_js_shell(data, response.body&.bytesize.to_i) if data[:likely_js_shell]
        data
      end
      module_function :build_data
      private_class_method :build_data

      def resolve_inspect_strategy(strategy, deep:)
        name = (strategy || :auto).to_sym
        return :botasaurus if deep && name == :auto && MCP::Runtime.botasaurus_configured?

        name
      end
      module_function :resolve_inspect_strategy
      private_class_method :resolve_inspect_strategy

      def html_present?(recon, response)
        recon.html_response && !response.body.to_s.empty?
      end
      module_function :html_present?
      private_class_method :html_present?

      def likely_js_shell?(recon, response)
        return false unless html_present?(recon, response)
        return false if recon.articles_count.positive?
        return false if recon.blocked_surface || recon.surface_category == :blocked_surface

        return true if recon.surface_category == :app_shell

        response.body.bytesize >= JS_SHELL_MIN_BODY_BYTES &&
          SurfaceCategory.coerce(recon.surface_category).weak?
      end
      module_function :likely_js_shell?
      private_class_method :likely_js_shell?

      def redirect_summary(recon)
        {
          requested_url: recon.requested_url,
          final_url: recon.final_url,
          status: recon.status,
          scheme_downgrade: recon.scheme_downgrade
        }
      end
      module_function :redirect_summary
      private_class_method :redirect_summary

      def log_js_shell(data, body_bytesize)
        Log.debug(
          "Diagnostics js_shell: bytesize=#{body_bytesize} surface_category=#{data[:surface_category]}"
        )
      end
      module_function :log_js_shell
      private_class_method :log_js_shell

      def safe_parsed_body(response)
        return unless response.html_response?

        response.parsed_body
      rescue RequestService::UnsupportedResponseContentType
        nil
      end
      module_function :safe_parsed_body
      private_class_method :safe_parsed_body

      def error_report(url, error) # rubocop:disable Metrics/MethodLength -- error hash mirrors success report shape
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
