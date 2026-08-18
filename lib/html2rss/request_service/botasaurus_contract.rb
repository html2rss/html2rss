# frozen_string_literal: true

require 'json'

module Html2rss
  class RequestService
    ##
    # Maps html2rss request/response handling to botasaurus-scrape-api OpenAPI 2.0
    # +ScrapeRequest+ / +ScrapeSuccess+ / +ScrapeError+ (sibling +openapi.yaml+).
    class BotasaurusContract # rubocop:disable Metrics/ClassLength -- Success/Error envelopes stay with the owner
      # Closed sets from OpenAPI ExecutionMode / NavigationMode / ErrorCategory.
      EXECUTION_MODES = %w[auto request browser].freeze
      NAVIGATION_MODES = %w[auto get google_get google_get_bypass organic_get].freeze
      ERROR_CATEGORIES = %w[timeout challenge_block navigation_error metadata_error validation].freeze

      # ScrapeRequest properties except +url+ (html2rss supplies the target URL).
      REQUEST_OPTION_KEYS = %i[
        execution_mode navigation_mode max_retries wait_for_selector wait_timeout_seconds
        scroll block_images block_images_and_css block_trackers
        wait_for_complete_page_load user_agent headers cookies window_size lang headless proxy
      ].freeze

      # OpenAPI WindowSize required keys (positive integers).
      WINDOW_SIZE_PROPERTIES = %i[width height].freeze

      # Published wait default, plus the API clamp ceiling (`[1, 20]` in OpenAPI description).
      # Config admission rejects waits above the ceiling instead of sending values that would be clamped.
      MIN_WAIT_TIMEOUT_SECONDS = 1
      MAX_WAIT_TIMEOUT_SECONDS = 20
      DEFAULT_WAIT_TIMEOUT_SECONDS = 15

      # OpenAPI max_retries maximum (default 2 is applied upstream when omitted).
      MAX_RETRIES = 3

      # Allowlisted ScrapeDiagnostics keys nested under diagnostics.
      DIAGNOSTICS_KEYS = %w[request_id attempts strategy_used render_ms execution_tier challenge].freeze
      CHALLENGE_KEYS = %w[blocked detected marker].freeze

      # Remaining seconds at or below which Botasaurus retries are disabled.
      TIGHT_BUDGET_SECONDS = 12

      # Seconds reserved from remaining budget before setting wait_timeout_seconds.
      BUDGET_WAIT_RESERVE_SECONDS = 2

      ##
      # Parsed OpenAPI ScrapeSuccess envelope (HTTP 200).
      class Success
        # Per-body size cap for captured XHR JSON (defense-in-depth vs upstream).
        MAX_XHR_BODY_BYTES = 500_000
        # Aggregate size cap across all captured XHR bodies.
        MAX_XHR_AGGREGATE_BYTES = 2_000_000

        # @param payload [Hash{String => Object}] parsed ScrapeSuccess object
        def initialize(payload:)
          @payload = payload
          html
          diagnostics
        end

        # @return [String] rendered HTML body
        def html
          value = payload['html']
          raise BotasaurusServiceError, 'Botasaurus scrape success requires html' unless value.is_a?(String)

          value
        end

        # @return [Hash{String => String}] normalized response headers (null → {})
        def headers
          raw_headers = payload['headers']
          return {} unless raw_headers.is_a?(Hash) && raw_headers.any?

          raw_headers.to_h { |key, value| [key.to_s, value.to_s] }
        end

        # @return [Integer, nil] document status_code when present
        def status
          status_code = payload['status_code']
          status_code.is_a?(Integer) ? status_code : nil
        end

        # @return [String, nil] final URL reported by upstream
        def final_url = payload['final_url']

        # @return [Hash{String => Object}] diagnostics plus success-only metadata_error (frozen)
        def transport_meta
          meta = diagnostics.dup
          meta['metadata_error'] = metadata_error if metadata_error
          meta.freeze
        end

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

        attr_reader :payload

        def diagnostics = BotasaurusContract.diagnostics_from(payload)

        def metadata_error
          value = payload['metadata_error']
          value.is_a?(String) && !value.empty? ? value : nil
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
      # Parsed OpenAPI ScrapeError envelope (HTTP 400/403/422/502/504).
      class Error
        # @param payload [Hash{String => Object}] parsed ScrapeError object
        # @param transport_status [Integer] HTTP status returned by Botasaurus
        def initialize(payload:, transport_status:)
          @payload = payload
          @transport_status = transport_status
          error
          error_category
          diagnostics
        end

        # @return [Boolean] true when upstream classified request as challenge blocked
        def challenge_block? = error_category == 'challenge_block'

        # @return [Boolean] true when the scrape envelope reports a timeout
        def timeout?
          transport_status == 504 || error_category == 'timeout'
        end

        # @return [String] normalized challenge error message
        def challenge_message
          [error, challenge_marker].find { |value| value.is_a?(String) && !value.empty? } ||
            'Botasaurus challenge block detected.'
        end

        # @return [String] actionable upstream failure summary
        def failure_message
          details = ["status=#{transport_status}", "error_category=#{error_category}", "error=#{error}"]
          details << "request_id=#{request_id}" if request_id
          "Botasaurus scrape failed (#{details.join(', ')})."
        end

        private

        attr_reader :payload, :transport_status

        def error
          value = payload['error']
          raise BotasaurusServiceError, 'Botasaurus scrape error requires error' unless value.is_a?(String)

          value
        end

        def error_category
          value = payload['error_category']
          return value if ERROR_CATEGORIES.include?(value)

          raise BotasaurusServiceError, 'Botasaurus scrape error requires error_category'
        end

        def diagnostics = BotasaurusContract.diagnostics_from(payload)

        def request_id = diagnostics['request_id']

        def challenge_marker
          challenge = diagnostics['challenge']
          challenge.is_a?(Hash) ? challenge['marker'] : nil
        end
      end

      ##
      # @param payload [Hash{String => Object}] scrape envelope
      # @return [Hash{String => Object}] allowlisted diagnostics (frozen)
      # @raise [BotasaurusServiceError] when diagnostics or request_id are missing
      def self.diagnostics_from(payload)
        raw = payload['diagnostics']
        raise BotasaurusServiceError, 'Botasaurus scrape envelope requires diagnostics' unless raw.is_a?(Hash)
        raise BotasaurusServiceError, 'Botasaurus diagnostics require request_id' if raw['request_id'].to_s.empty?

        sliced = raw.slice(*DIAGNOSTICS_KEYS)
        sliced['challenge'] = compact_challenge(sliced['challenge'])
        sliced.compact.freeze
      end

      # @param challenge [Object] diagnostics.challenge value
      # @return [Hash{String => Object}, nil]
      def self.compact_challenge(challenge)
        return unless challenge.is_a?(Hash)

        challenge.slice(*CHALLENGE_KEYS).compact
      end
      private_class_method :compact_challenge

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
      # @option options [Boolean] :scroll
      # @option options [Boolean] :block_images
      # @option options [Boolean] :block_images_and_css
      # @option options [Boolean] :block_trackers
      # @option options [Boolean] :wait_for_complete_page_load
      # @option options [Boolean] :headless
      # @option options [String] :proxy
      # @option options [String] :user_agent
      # @option options [Hash] :window_size
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
      # @return [Success, Error]
      # @raise [BotasaurusServiceError] when payload is not a scrape envelope
      def parse_response(transport_response)
        payload = json_object(transport_response.body.to_s)
        return Success.new(payload:) if transport_response.status == 200

        Error.new(payload:, transport_status: transport_response.status)
      end

      private

      attr_reader :url, :headers, :options, :remaining_timeout_seconds

      def json_object(body)
        payload = JSON.parse(body)
        return payload if payload.is_a?(Hash)

        raise BotasaurusServiceError, 'Botasaurus response must be a JSON object'
      rescue JSON::ParserError => error
        raise BotasaurusServiceError, "Botasaurus response JSON parse failed: #{error.message}"
      end

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
