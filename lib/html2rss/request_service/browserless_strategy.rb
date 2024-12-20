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
      # return [Response]
      def execute
        Puppeteer.connect(browser_ws_endpoint:) do |browser|
          PuppetCommander.new(ctx, browser).call
        ensure
          browser.disconnect
        end
      end

      def browser_ws_endpoint
        @browser_ws_endpoint ||= begin
          api_token = ENV.fetch('BROWSERLESS_IO_API_TOKEN', '6R0W53R135510')
          ws_url = ENV.fetch('BROWSERLESS_IO_WEBSOCKET_URL', 'ws://127.0.0.1:3000')

          "#{ws_url}?token=#{api_token}"
        end
      end
    end
  end
end
