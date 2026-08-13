# frozen_string_literal: true

require 'faraday'
require 'json'

module Html2rss
  class RequestService
    ##
    # Strategy to delegate fetching to a Botasaurus scrape API.
    class BotasaurusStrategy < Strategy
      private

      def fetch
        parsed_response = post_scrape_request
        raise_if_challenge_blocked!(parsed_response)
        raise_if_upstream_failed!(parsed_response)
        build_response(parsed_response)
      end

      def post_scrape_request
        transport_response = client.post('/scrape', JSON.generate(contract.request_payload), content_type_header)
        contract.parse_response(transport_response)
      end

      def build_response(parsed_response)
        Response.new(
          body: parsed_response.html,
          headers: parsed_response.headers,
          url: response_url(parsed_response.final_url),
          status: parsed_response.status,
          transport_meta: parsed_response.transport_meta
        )
      end

      def raise_if_challenge_blocked!(parsed_response)
        return unless parsed_response.challenge_block?

        raise BlockedSurfaceDetected, "Blocked surface detected: #{parsed_response.challenge_message}"
      end

      def raise_if_upstream_failed!(parsed_response)
        return unless parsed_response.upstream_failure?

        raise BotasaurusConnectionFailed, parsed_response.upstream_failure_message
      end

      def response_url(final_url)
        return ctx.url if final_url.nil?

        Html2rss::Url.from_absolute(final_url)
      rescue ArgumentError
        ctx.url
      end

      def contract
        @contract ||= BotasaurusContract.new(
          url: ctx.url,
          options: ctx.request.fetch(:botasaurus, {}),
          remaining_timeout_seconds: attempt_timeout_seconds
        )
      end

      def client
        @client ||= Faraday.new(url: scraper_base_url.to_s, request: request_options)
      end

      def request_options
        { timeout: attempt_timeout_seconds.to_i }
      end

      def attempt_timeout_seconds
        @attempt_timeout_seconds ||= ctx.budget.effective_timeout_seconds(
          fallback: ctx.policy.total_timeout_seconds
        )
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

      def translate_connection_error(error)
        raise BotasaurusConnectionFailed, "Botasaurus connection failed: #{error.message}"
      end
    end
  end
end
