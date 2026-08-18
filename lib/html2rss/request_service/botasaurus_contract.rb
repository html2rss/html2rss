# frozen_string_literal: true

require 'json'

module Html2rss
  class RequestService
    ##
    # Maps html2rss request/response handling to botasaurus-scrape-api OpenAPI
    # +ScrapeRequest+ / +ScrapeResponse+ (see sibling +openapi.yaml+).
    class BotasaurusContract
      # Closed sets from OpenAPI ScrapeRequest / ScrapeResponse.error_category.
      EXECUTION_MODES = %w[auto request browser].freeze
      NAVIGATION_MODES = %w[auto get google_get google_get_bypass organic_get].freeze
      ERROR_CATEGORIES = %w[timeout challenge_block navigation_error metadata_error].freeze

      # ScrapeRequest properties except +url+ (html2rss supplies the target URL).
      REQUEST_OPTION_KEYS = %i[
        execution_mode navigation_mode max_retries wait_for_selector wait_timeout_seconds
        scroll scroll_to_bottom block_images block_images_and_css block_trackers
        wait_for_complete_page_load user_agent headers cookies window_size lang headless proxy
      ].freeze

      # Published wait default, plus the API clamp ceiling (`[1, 20]` in OpenAPI description).
      # Config admission rejects waits above the ceiling instead of sending values that would be clamped.
      MIN_WAIT_TIMEOUT_SECONDS = 1
      MAX_WAIT_TIMEOUT_SECONDS = 20
      DEFAULT_WAIT_TIMEOUT_SECONDS = 15

      # OpenAPI max_retries maximum (default 2 is applied upstream when omitted).
      MAX_RETRIES = 3

      # OpenAPI window_size runtime constraint (exactly two positive integers).
      WINDOW_SIZE_LENGTH = 2

      # Allowlisted ScrapeResponse diagnostic keys exposed as Response#transport_meta.
      META_KEYS = %w[
        request_id strategy_used render_ms challenge_detected blocked_detected attempts
        error_category execution_tier detected_challenge metadata_error
      ].freeze

      # Remaining seconds at or below which Botasaurus retries are disabled.
      TIGHT_BUDGET_SECONDS = 12

      # Seconds reserved from remaining budget before setting wait_timeout_seconds.
      BUDGET_WAIT_RESERVE_SECONDS = 2

      # Parsed Botasaurus ScrapeResponse wrapper.
      class ParsedResponse
        # Per-body size cap for captured XHR JSON (defense-in-depth vs upstream).
        MAX_XHR_BODY_BYTES = 500_000
        # Aggregate size cap across all captured XHR bodies.
        MAX_XHR_AGGREGATE_BYTES = 2_000_000

        # @param payload [Hash{String => Object}] parsed ScrapeResponse object
        # @param transport_status [Integer] HTTP status returned by Botasaurus
        def initialize(payload:, transport_status:)
          @payload = payload
          @transport_status = transport_status
        end

        # @return [Boolean] true when upstream classified request as challenge blocked
        def challenge_block? = error_category == 'challenge_block'

        # @return [Boolean] true when the scrape envelope reports a timeout
        def timeout?
          transport_status == 504 || error_category == 'timeout'
        end

        # @return [Boolean] true when scrape transport is not 200 or error is present
        def upstream_failure?
          transport_status != 200 || error_message?
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

        # @return [String] rendered HTML body (OpenAPI default is empty string)
        def html = payload.fetch('html', '').to_s

        # @return [Hash{String => String}] normalized response headers (null → {})
        def headers
          raw_headers = payload['headers']
          return {} unless raw_headers.is_a?(Hash) && raw_headers.any?

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

        # @return [Array<Hash{String => Object}>] size-capped XHR/fetch captures (absent → [])
        def xhr_responses
          raw = payload['xhr_responses']
          return [] unless raw.is_a?(Array)

          aggregate_bytes = 0
          raw.filter_map do |entry|
            normalized = normalize_xhr_entry(entry)
            next unless normalized
            next unless (aggregate_bytes = advance_xhr_budget(normalized, aggregate_bytes))

            normalized
          end
        end

        private

        attr_reader :payload, :transport_status

        def error = payload['error']

        def request_id = payload['request_id']

        def error_category = payload['error_category']

        def error_message?
          value = error
          value.is_a?(String) ? !value.empty? : !value.nil?
        end

        def normalize_xhr_entry(entry)
          return unless entry.is_a?(Hash)

          body = xhr_field(entry, :body)
          return unless body.is_a?(String) && !body.empty?

          {
            'url' => xhr_field(entry, :url).to_s,
            'body' => body,
            'headers' => xhr_headers(xhr_field(entry, :headers)),
            'status_code' => xhr_status_code(xhr_field(entry, :status_code))
          }
        end

        # @return [Integer, nil] next aggregate byte total when accepted
        def advance_xhr_budget(normalized, aggregate_bytes)
          body_bytes = normalized.fetch('body').bytesize
          return if body_bytes > MAX_XHR_BODY_BYTES
          return if aggregate_bytes + body_bytes > MAX_XHR_AGGREGATE_BYTES

          aggregate_bytes + body_bytes
        end

        def xhr_field(entry, key)
          entry[key.to_s] || entry[key]
        end

        def xhr_headers(raw)
          return {} unless raw.is_a?(Hash)

          raw.to_h { |key, value| [key.to_s, value.to_s] }
        end

        def xhr_status_code(value)
          value.is_a?(Integer) ? value : nil
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

      # @return [Hash] payload for POST /scrape (explicit options plus budget clamp-downs)
      def request_payload
        payload = { url: url.to_s }.merge(filtered_options)
        forwarded_headers = merged_headers
        payload[:headers] = forwarded_headers if forwarded_headers&.any?
        clamp_for_budget(payload)
      end

      # @param transport_response [Faraday::Response] upstream HTTP response
      # @return [ParsedResponse]
      # @raise [BotasaurusServiceError] when payload is not a JSON object
      def parse_response(transport_response)
        payload = JSON.parse(transport_response.body.to_s)
        raise BotasaurusServiceError, 'Botasaurus response must be a JSON object' unless payload.is_a?(Hash)

        ParsedResponse.new(payload:, transport_status: transport_response.status)
      rescue JSON::ParserError => error
        raise BotasaurusServiceError, "Botasaurus response JSON parse failed: #{error.message}"
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
        REQUEST_OPTION_KEYS.each_with_object({}) do |key, normalized|
          normalized[key] = options[key] if options.key?(key)
        end
      end

      def clamp_for_budget(payload)
        remaining = remaining_timeout_seconds
        clamped = payload.dup
        unless remaining.nil?
          apply_tight_retries!(clamped, remaining)
          apply_budget_wait!(clamped, remaining)
        end
        cap_wait_timeout!(clamped)
        clamped
      end

      def apply_tight_retries!(payload, remaining)
        payload[:max_retries] = 0 if remaining <= TIGHT_BUDGET_SECONDS
      end

      def apply_budget_wait!(payload, remaining)
        budget_wait = budget_wait_seconds(remaining)
        configured = payload[:wait_timeout_seconds]
        if configured
          payload[:wait_timeout_seconds] = [configured, budget_wait].min
        elsif budget_wait < DEFAULT_WAIT_TIMEOUT_SECONDS
          payload[:wait_timeout_seconds] = budget_wait
        end
      end

      def budget_wait_seconds(remaining)
        reserved = [MIN_WAIT_TIMEOUT_SECONDS, (remaining - BUDGET_WAIT_RESERVE_SECONDS).floor].max
        [reserved, MAX_WAIT_TIMEOUT_SECONDS].min
      end

      def cap_wait_timeout!(payload)
        wait = payload[:wait_timeout_seconds]
        return unless wait

        payload[:wait_timeout_seconds] = [wait, MAX_WAIT_TIMEOUT_SECONDS].min
      end
    end
  end
end
