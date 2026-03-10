# frozen_string_literal: true

require 'puppeteer'

module Html2rss
  class RequestService
    ##
    # Browserless.io strategy to request websites.
    #
    # Provide the WebSocket URL and your API token via environment variables:
    # - BROWSERLESS_IO_WEBSOCKET_URL
    # - BROWSERLESS_IO_API_TOKEN
    #
    # To use this strategy, you need to have a Browserless.io account or run a
    # local Browserless.io instance.
    #
    # @see https://www.browserless.io/
    #
    # To run a local Browserless.io instance, you can use the following Docker command:
    #
    # ```sh
    # docker run \
    #   --rm \
    #   -p 3000:3000 \
    #   -e "CONCURRENT=10" \
    #   -e "TOKEN=6R0W53R135510" \
    #   ghcr.io/browserless/chromium
    # ```
    #
    # When running locally, you can skip setting the environment variables, as above commands
    # are aligned with the default values.
    # @see https://github.com/browserless/browserless/pkgs/container/chromium
    class BrowserlessStrategy < Strategy
      ##
      # Executes a Browserless-backed request with the shared request policy.
      #
      # @return [Response] normalized request response
      # @raise [RequestTimedOut] if the browser session exceeds the configured timeout
      def execute
        validate_request!
        execute_browserless_request
      rescue Puppeteer::TimeoutError => error
        raise RequestTimedOut, error.message
      end

      ##
      # @return [String] the Browserless websocket endpoint with token query param
      def browser_ws_endpoint
        @browser_ws_endpoint ||= begin
          ws_url = ENV.fetch('BROWSERLESS_IO_WEBSOCKET_URL', 'ws://127.0.0.1:3000')
          api_token = browserless_api_token(ws_url)

          "#{ws_url}?token=#{api_token}"
        end
      end

      private

      def validate_request!
        ctx.budget.consume!
        ctx.policy.validate_request!(url: ctx.url, origin_url: ctx.origin_url, relation: ctx.relation)
      end

      def execute_browserless_request
        Puppeteer.connect(browser_ws_endpoint:, protocol_timeout: protocol_timeout_ms) do |browser|
          PuppetCommander.new(ctx, browser).call
        ensure
          browser.disconnect
        end
      end

      def protocol_timeout_ms
        ctx.policy.total_timeout_seconds * 1000
      end

      def browserless_api_token(ws_url)
        ENV.fetch('BROWSERLESS_IO_API_TOKEN') do
          return '6R0W53R135510' if ws_url == 'ws://127.0.0.1:3000'

          raise ArgumentError, 'BROWSERLESS_IO_API_TOKEN is required for custom Browserless endpoints'
        end
      end
    end
  end
end
