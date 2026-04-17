# frozen_string_literal: true

require 'faraday'
require 'json'

module Html2rss
  class RequestService
    ##
    # Strategy to delegate fetching to a Botasaurus scrape API.
    class BotasaurusStrategy < Strategy
      # Default Botasaurus navigation mode.
      DEFAULT_NAVIGATION_MODE = 'auto'
      # Default retry count used by Botasaurus auto mode.
      DEFAULT_MAX_RETRIES = 2
      # Default Botasaurus headless flag.
      DEFAULT_HEADLESS = false
      # Fallback response headers when upstream omits headers.
      DEFAULT_HEADERS = { 'content-type' => 'text/html' }.freeze

      ##
      # Executes a Botasaurus-backed request with shared request policy guards.
      #
      # @return [Response] normalized request response
      # @raise [BotasaurusConfigurationError] when BOTASAURUS_SCRAPER_URL is missing or invalid
      # @raise [BotasaurusConnectionFailed] when Botasaurus cannot be reached or returns an invalid payload
      # @raise [RequestTimedOut] when the Botasaurus request exceeds configured timeout
      def execute
        validate_request!
        transport_response = client.post('/scrape', JSON.generate(scrape_payload), content_type_header)
        build_response(parse_payload(transport_response), transport_response)
      rescue Faraday::TimeoutError, Timeout::Error => error
        raise RequestTimedOut, error.message
      rescue JSON::ParserError => error
        raise BotasaurusConnectionFailed, "Botasaurus response JSON parse failed: #{error.message}"
      rescue Faraday::ConnectionFailed, Faraday::SSLError => error
        raise BotasaurusConnectionFailed, "Botasaurus connection failed: #{error.message}"
      end

      private

      def validate_request!
        ctx.budget.consume!
        ctx.policy.validate_request!(url: ctx.url, origin_url: ctx.origin_url, relation: ctx.relation)
      end

      def build_response(response_payload, transport_response)
        body = response_payload.fetch('html').to_s
        ResponseGuard.new(policy: ctx.policy).inspect_body!(body)

        Response.new(
          body:,
          headers: response_headers(response_payload),
          url: response_url(response_payload),
          status: response_status(response_payload, transport_response)
        )
      end

      def parse_payload(transport_response)
        payload = JSON.parse(transport_response.body.to_s)
        raise BotasaurusConnectionFailed, 'Botasaurus response must be a JSON object' unless payload.is_a?(Hash)
        unless payload.key?('html')
          raise BotasaurusConnectionFailed, "Botasaurus response missing required 'html' field"
        end

        raise_if_challenge_blocked!(payload)

        payload
      end

      def raise_if_challenge_blocked!(response_payload)
        return unless response_payload['error_category'] == 'challenge_block'

        message = response_payload['error'] || 'Botasaurus challenge block detected.'
        raise BlockedSurfaceDetected, "Blocked surface detected: #{message}"
      end

      def response_headers(response_payload)
        raw_headers = response_payload['headers']
        return DEFAULT_HEADERS.dup unless raw_headers.is_a?(Hash) && raw_headers.any?

        raw_headers.to_h { |key, value| [key.to_s, value.to_s] }
      end

      def response_status(response_payload, transport_response)
        status_code = response_payload['status_code']
        status_code.is_a?(Integer) ? status_code : transport_response.status
      end

      def response_url(response_payload)
        return ctx.url unless response_payload['final_url']

        Html2rss::Url.from_absolute(response_payload['final_url'])
      rescue ArgumentError
        ctx.url
      end

      def client
        @client ||= Faraday.new(url: scraper_base_url.to_s, request: request_options)
      end

      def request_options
        { timeout: ctx.policy.total_timeout_seconds }
      end

      def scrape_payload
        {
          url: ctx.url.to_s,
          navigation_mode: DEFAULT_NAVIGATION_MODE,
          max_retries: DEFAULT_MAX_RETRIES,
          headless: DEFAULT_HEADLESS
        }
      end

      def content_type_header
        { 'Content-Type' => 'application/json' }
      end

      def scraper_base_url
        @scraper_base_url ||= begin
          configured = ENV.fetch('BOTASAURUS_SCRAPER_URL') do
            raise BotasaurusConfigurationError, 'BOTASAURUS_SCRAPER_URL is required for strategy=botasaurus.'
          end
          Html2rss::Url.for_channel(configured)
        rescue ArgumentError => error
          raise BotasaurusConfigurationError, "BOTASAURUS_SCRAPER_URL is invalid: #{error.message}"
        end
      end
    end
  end
end
