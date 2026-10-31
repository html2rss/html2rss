# frozen_string_literal: true

require 'httpx'
require 'json'
require 'securerandom'

module Html2rss
  class RequestService
    ##
    # Strategy to delegate fetching to a Botasaurus scrape API.
    class BotasaurusStrategy < Strategy # rubocop:disable Metrics/ClassLength -- transport + cookie-jar retry stay co-located
      # Content-Type negotiation for the scrape API transport hop.
      TRANSPORT_ACCEPT = 'application/json'
      # Disable compressed bodies so HTTPX returns raw JSON without implicit decoding surprises.
      TRANSPORT_ENCODING = 'identity'
      # Correlates each POST /scrape with botasaurus-scrape-api request logs.
      REQUEST_ID_HEADER = 'X-Request-Id'

      private

      # Replays stored clearance cookies; a block while holding them evicts the jar and retries once without.
      def fetch
        stored = jar.stored
        scrape(stored)
      rescue BlockedSurfaceDetected
        raise if stored.empty?

        jar.evict(stored)
        scrape({})
      end

      def scrape(stored)
        parsed_response = post_scrape_request(stored)
        raise_from_error!(parsed_response) if parsed_response.is_a?(BotasaurusContract::Error)

        response = build_response(parsed_response)
        ResponseGuard.new(policy: ctx.policy).inspect_body!(response.body) if stored.any?
        jar.refresh(stored, response.cookies)
        response
      end

      def jar
        @jar ||= CookieJar.new(
          host: ctx.url.host, scraper_base_url: scraper_base_url.to_s, proxy: botasaurus_options[:proxy],
          user_agent: botasaurus_options[:user_agent] || ctx.headers['User-Agent']
        )
      end

      def botasaurus_options = ctx.request.fetch(:botasaurus, {})

      def post_scrape_request(stored)
        request_id = SecureRandom.uuid
        Log.debug("#{self.class}: POST /scrape #{REQUEST_ID_HEADER}=#{request_id}")
        contract = contract(stored)
        payload = JSON.generate(contract.request_payload)
        response = client.post(scrape_endpoint, body: payload, headers: post_headers(request_id))
        raise response.error if response.is_a?(HTTPX::ErrorResponse)

        contract.parse_response(response)
      end

      def scrape_endpoint = "#{scraper_base_url.to_s.chomp('/')}/scrape"

      def build_response(parsed_response)
        Response.new(
          body: parsed_response.html,
          headers: parsed_response.headers,
          url: response_url(parsed_response.final_url),
          status: parsed_response.status,
          transport_meta: parsed_response.transport_meta,
          captured_responses: parsed_response.xhr_responses,
          cookies: parsed_response.cookies
        )
      end

      def raise_from_error!(error)
        err = if error.challenge_block?
                BlockedSurfaceDetected.new("Blocked surface detected: #{error.challenge_message}")
              elsif error.timeout?
                log_timeout!(reason: 'botasaurus_upstream')
                RequestTimedOut.new(error.failure_message, timeout_phase: error.timeout_phase)
              else
                BotasaurusServiceError.new(error.failure_message)
              end
        err.transport_meta = error.transport_meta
        raise err
      end

      def response_url(final_url)
        return ctx.url if final_url.nil?

        Html2rss::Url.from_absolute(final_url)
      rescue Html2rss::Url::InvalidUrlError
        ctx.url
      end

      def contract(stored)
        BotasaurusContract.new(url: ctx.url, headers: ctx.headers, options: botasaurus_options, stored_cookies: stored)
      end

      def client
        timeout = attempt_timeout_seconds.to_f
        @client ||= HTTPX.with(headers: client_headers, timeout: client_timeouts(timeout), resolver_class: :system)
      end

      def client_timeouts(timeout)
        {
          operation_timeout: timeout,
          connect_timeout: [ctx.policy.connect_timeout_seconds, timeout].min,
          read_timeout: timeout,
          request_timeout: timeout,
          total_request_timeout: timeout
        }
      end

      def client_headers
        {
          'User-Agent' => Config::RequestHeaders::DEFAULT_USER_AGENT,
          'Accept' => TRANSPORT_ACCEPT,
          'Accept-Encoding' => TRANSPORT_ENCODING
        }
      end

      def post_headers(request_id)
        { 'Content-Type' => 'application/json', REQUEST_ID_HEADER => request_id }
      end

      def attempt_timeout_seconds
        @attempt_timeout_seconds ||= begin
          budget = ctx.budget.effective_timeout_seconds(fallback: ctx.policy.total_timeout_seconds)
          [budget, BotasaurusContract::SCRAPE_TIMEOUT_SECONDS + BotasaurusContract::TRANSPORT_BUFFER_SECONDS].min
        end
      end

      def scraper_base_url
        @scraper_base_url ||= begin
          configured = ENV.fetch('BOTASAURUS_SCRAPER_URL') do
            raise BotasaurusConfigurationError, 'BOTASAURUS_SCRAPER_URL is required for strategy=botasaurus.'
          end
          Html2rss::Url.for_channel(configured)
        rescue Html2rss::Url::InvalidUrlError => error
          raise BotasaurusConfigurationError, "BOTASAURUS_SCRAPER_URL is invalid: #{error.message}"
        end
      end

      def translate_connection_error(error)
        raise BotasaurusConnectionFailed, "Botasaurus connection failed: #{error.message}"
      end

      def timeout_error?(error) = error.is_a?(HTTPX::TimeoutError) || super

      def connection_error?(error) = error.is_a?(HTTPX::ConnectionError) || error.is_a?(HTTPX::TLSError) || super
    end
  end
end
