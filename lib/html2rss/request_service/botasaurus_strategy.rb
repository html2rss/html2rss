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

      # `scrape` guards each body itself so the cookie replay can fall back on a block.
      def skip_postflight? = true

      # With a stored jar, tries the cheap HTTP tier first; cookies never reach the browser tier,
      # so a block falls back to a plain scrape without them.
      def fetch
        stored = jar.stored
        return scrape({}) unless replay?(stored)

        replay(stored)
      end

      def replay?(stored) = botasaurus_options[:execution_mode] != 'browser' && jar.replayable?(stored)

      def replay(stored)
        response = scrape(stored, execution_mode: 'request')
        jar.replayed(:pass, stored)
        response
      rescue BlockedSurfaceDetected
        jar.replayed(:block, stored)
        scrape({})
      end

      def scrape(stored, overrides = {})
        parsed_response = post_scrape_request(stored, overrides)
        raise_from_error!(parsed_response) if parsed_response.is_a?(BotasaurusContract::Error)

        response = build_response(parsed_response)
        guard_body!(response.body)
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

      def post_scrape_request(stored, overrides)
        request_id = SecureRandom.uuid
        Log.debug("#{self.class}: POST /scrape #{REQUEST_ID_HEADER}=#{request_id}")
        contract = contract(stored, overrides)
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
          captured_responses: public_captures(parsed_response.xhr_responses),
          cookies: parsed_response.cookies
        )
      end

      # A capture feeds article extraction only when its URL passes the public-network check applied to the
      # final URL. Cross-origin public hosts (APIs) are legitimate; anything else is dropped, not fatal.
      def public_captures(captures)
        denials = {}
        captures.select { |capture| public_capture?(capture, denials) }
      end

      # +denials+ memoizes the verdict per host for one call, so a host costs a single DNS lookup.
      def public_capture?(capture, denials)
        url = Url.from_absolute_web(capture.fetch('url'))
        reason = denials.fetch(url.host) { denials[url.host] = denial_reason(url) }
        return true unless reason

        log_dropped(reason, capture)
        false
      rescue Html2rss::Url::InvalidUrlError => error
        log_dropped(error.class.name, capture)
        false
      end

      def denial_reason(url)
        ctx.policy.enforce_public_network!(url)
        nil
      rescue PrivateNetworkDenied => error
        error.class.name
      end

      def log_dropped(reason, capture)
        Log.event(:warn, 'botasaurus.capture_dropped', reason:, endpoint: Response.redacted_endpoint(capture))
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

      # The remote browser follows redirects itself, so its final URL gets the same hop check HTTPX applies.
      def response_url(final_url)
        url = parse_final_url(final_url)
        return ctx.url unless url

        ctx.policy.validate_redirect!(from_url: ctx.url, to_url: url, origin_url: ctx.origin_url,
                                      relation: ctx.relation, advertisement: ctx.advertisement)
        url
      end

      def parse_final_url(final_url)
        Html2rss::Url.from_absolute_web(final_url)
      rescue Html2rss::Url::InvalidUrlError
        nil
      end

      def contract(stored, overrides)
        BotasaurusContract.new(
          url: ctx.url, headers: ctx.headers, options: botasaurus_options.merge(overrides), stored_cookies: stored
        )
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
          budget = ctx.budget.effective_timeout_seconds
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
