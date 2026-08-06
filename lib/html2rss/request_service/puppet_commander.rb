# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Commands the Puppeteer Browser to the website and builds the Response.
    #
    # Public interface is {#call}; page setup, navigation, and body collection
    # are private orchestration steps.
    class PuppetCommander
      # Request header names that must not be forwarded to the browser session.
      BROWSER_UNSAFE_HEADERS = %w[
        host connection content-length transfer-encoding
        sec-fetch-dest sec-fetch-mode sec-fetch-site sec-fetch-user
        upgrade-insecure-requests
      ].to_set.freeze

      # @param ctx [Context]
      # @param browser [Puppeteer::Browser]
      # @param skip_request_resources [Set<String>] the resource types not to request
      # @param referer [String] the referer to use for the request
      def initialize(ctx,
                     browser,
                     skip_request_resources: %w[stylesheet image media font].to_set,
                     referer: [ctx.url.scheme, ctx.url.host].join('://'))
        @ctx = ctx
        @browser = browser
        @referer = referer
        @navigation_guards = NavigationGuards.new(ctx:, skip_request_resources:)
        @preload_runner = PreloadRunner.new(ctx:)
      end

      ##
      # Visits the request URL and normalizes the page into a response object.
      #
      # @return [Response] rendered page response
      def call
        page = new_page
        navigation_response = navigate_to_destination(page, ctx.url)
        preload_runner.call(page)
        navigation_guards.raise_deferred_error!
        final_navigation_response = navigation_guards.latest_navigation_response || navigation_response
        navigation_guards.validate_final!(final_navigation_response)
        build_response(page, final_navigation_response)
      ensure
        page&.close
      end

      private

      attr_reader :ctx, :browser, :referer, :navigation_guards, :preload_runner

      def new_page
        page = browser.new_page
        configure_page(page)
        navigation_guards.install!(page)
        page
      end

      def configure_page(page)
        page.extra_http_headers = browser_headers
        page.default_navigation_timeout = navigation_timeout_ms
        page.default_timeout = navigation_timeout_ms
      end

      def navigate_to_destination(page, url)
        navigation_guards.begin_navigation!
        page.goto(url, wait_until: 'networkidle0', referer:, timeout: navigation_timeout_ms).tap do
          navigation_guards.raise_deferred_error!
        end
      rescue StandardError
        navigation_guards.raise_deferred_error!

        raise
      end

      def navigation_timeout_ms
        ctx.budget.effective_timeout_ms(fallback: ctx.policy.total_timeout_seconds)
      end

      def browser_headers
        ctx.headers.reject { |key, _| BROWSER_UNSAFE_HEADERS.include?(key.to_s.downcase) }
      end

      def build_response(page, navigation_response)
        Response.new(
          body: page.content,
          headers: navigation_response&.headers || {},
          url: NavigationGuards.response_url(navigation_response, ctx.url),
          status: navigation_response&.status
        )
      end
    end
  end
end
