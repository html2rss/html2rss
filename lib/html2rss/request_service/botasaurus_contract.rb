# frozen_string_literal: true

require 'json'

module Html2rss
  class RequestService
    ##
    # Maps html2rss request/response handling to the botasaurus-scrape-api contract.
    class BotasaurusContract
      # Default Botasaurus scrape options when no explicit config is provided.
      DEFAULT_OPTIONS = {
        execution_mode: 'auto',
        navigation_mode: 'auto',
        max_retries: 1,
        headless: false
      }.freeze

      # Allowlisted request.botasaurus keys forwarded to upstream.
      OPTION_KEYS = %i[
        execution_mode
        navigation_mode
        max_retries
        wait_for_selector
        wait_timeout_seconds
        scroll
        scroll_to_bottom
        block_images
        block_images_and_css
        block_trackers
        wait_for_complete_page_load
        headless
        proxy
        user_agent
        window_size
        lang
        headers
        cookies
      ].freeze

      # Allowlisted upstream response keys exposed as Response#transport_meta.
      META_KEYS = %w[
        request_id strategy_used render_ms challenge_detected blocked_detected attempts error_category
        execution_tier detected_challenge
      ].freeze

      # Remaining seconds at or below which Botasaurus retries are disabled.
      TIGHT_BUDGET_SECONDS = 12

      # Seconds reserved from remaining budget before setting wait_timeout_seconds.
      BUDGET_WAIT_RESERVE_SECONDS = 2

      # Parsed Botasaurus response wrapper.
      class ParsedResponse
        # Fallback headers when upstream omits response headers.
        DEFAULT_HEADERS = { 'content-type' => 'text/html' }.freeze

        # @param payload [Hash{String => Object}] parsed Botasaurus response payload
        # @param transport_status [Integer] HTTP status returned by Botasaurus
        def initialize(payload:, transport_status:)
          @payload = payload
          @transport_status = transport_status
        end

        # @return [Boolean] true when upstream classified request as challenge blocked
        def challenge_block? = error_category == 'challenge_block'

        # @return [Boolean] true when upstream returned non-200 or an error payload
        def upstream_failure?
          transport_status != 200 || status != 200 || error_message?
        end

        # @return [String] normalized challenge error message
        def challenge_message
          error || 'Botasaurus challenge block detected.'
        end

        # @return [String] actionable upstream failure summary
        def upstream_failure_message
          details = ["status=#{status}"]
          details << "error_category=#{error_category}" if error_category
          details << "error=#{error}" if error
          details << "request_id=#{request_id}" if request_id
          "Botasaurus scrape failed (#{details.join(', ')})."
        end

        # @return [String] rendered HTML body from Botasaurus
        # @raise [BotasaurusConnectionFailed] when html is missing
        def html
          value = payload['html']
          raise BotasaurusConnectionFailed, "Botasaurus response missing required 'html' field" if value.nil?

          value.to_s
        end

        # @return [Hash{String => String}] normalized response headers
        def headers
          raw_headers = payload['headers']
          return DEFAULT_HEADERS.dup unless raw_headers.is_a?(Hash) && raw_headers.any?

          raw_headers.to_h { |key, value| [key.to_s, value.to_s] }
        end

        # @return [Integer] resolved status code (payload status_code or transport status)
        def status
          status_code = payload['status_code']
          status_code.is_a?(Integer) ? status_code : transport_status
        end

        # @return [String, nil] final URL reported by upstream
        def final_url = payload['final_url']

        # @return [Hash{String => Object}] allowlisted upstream telemetry (frozen)
        def transport_meta = payload.slice(*META_KEYS).compact.freeze

        private

        attr_reader :payload, :transport_status

        def error = payload['error']

        def request_id = payload['request_id']

        def error_category = payload['error_category']

        def error_message?
          value = error
          value.is_a?(String) ? !value.empty? : !value.nil?
        end
      end

      ##
      # @param url [Html2rss::Url] canonical URL to scrape
      # @param headers [Hash] request headers from context
      # @param options [Hash] validated request.botasaurus options
      # @param remaining_timeout_seconds [Numeric, nil] shared request budget remainder for clamps
      # @option options [String] :execution_mode
      # @option options [String] :navigation_mode
      # @option options [Integer] :max_retries
      # @option options [String] :wait_for_selector
      # @option options [Integer] :wait_timeout_seconds
      # @option options [Boolean] :block_images
      # @option options [Boolean] :block_images_and_css
      # @option options [Boolean] :block_trackers
      # @option options [Boolean] :wait_for_complete_page_load
      # @option options [Boolean] :headless
      # @option options [String] :proxy
      # @option options [String] :user_agent
      # @option options [Array<Integer>] :window_size
      # @option options [String] :lang
      # @option options [Hash] :cookies
      # @option options [Hash] :headers
      def initialize(url:, headers: {}, options: {}, remaining_timeout_seconds: nil)
        @url = url
        @headers = headers
        @options = options
        @remaining_timeout_seconds = remaining_timeout_seconds
      end

      # @return [Hash] payload for POST /scrape (budget-clamped when remaining is known)
      def request_payload
        payload = DEFAULT_OPTIONS.merge(filtered_options)
        forwarded_headers = merged_headers
        payload[:headers] = forwarded_headers if forwarded_headers&.any?
        payload.merge(url: url.to_s).then { clamp_for_budget(_1) }
      end

      # @param transport_response [Faraday::Response] upstream HTTP response
      # @return [ParsedResponse]
      # @raise [BotasaurusConnectionFailed] when payload is not valid JSON object
      def parse_response(transport_response)
        payload = JSON.parse(transport_response.body.to_s)
        raise BotasaurusConnectionFailed, 'Botasaurus response must be a JSON object' unless payload.is_a?(Hash)

        ParsedResponse.new(payload:, transport_status: transport_response.status)
      rescue JSON::ParserError => error
        raise BotasaurusConnectionFailed, "Botasaurus response JSON parse failed: #{error.message}"
      end

      private

      attr_reader :url, :headers, :options, :remaining_timeout_seconds

      def merged_headers
        explicit = options[:headers] || {}
        base = headers.is_a?(Hash) ? headers : {}
        merged = base.merge(explicit).transform_keys(&:to_s).compact
        merged.empty? ? nil : merged
      end

      def filtered_options
        OPTION_KEYS.each_with_object({}) do |key, normalized|
          normalized[key] = options[key] if options.key?(key)
        end
      end

      def clamp_for_budget(payload)
        remaining = remaining_timeout_seconds
        return payload if remaining.nil?

        clamped = payload.dup
        clamped[:max_retries] = 0 if remaining <= TIGHT_BUDGET_SECONDS
        budget_wait = [1, (remaining - BUDGET_WAIT_RESERVE_SECONDS).floor].max
        configured = clamped[:wait_timeout_seconds]
        clamped[:wait_timeout_seconds] = configured ? [configured, budget_wait].min : budget_wait
        clamped
      end
    end
  end
end
