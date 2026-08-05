# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Commands the Puppeteer Browser to the website and builds the Response.
    class PuppetCommander # rubocop:disable Metrics/ClassLength
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
        @skip_request_resources = skip_request_resources
        @referer = referer
        @navigation_guards = NavigationGuards.new(ctx:, skip_request_resources:)
      end

      ##
      # Visits the request URL and normalizes the page into a response object.
      #
      # @return [Response] rendered page response
      def call
        page = new_page
        navigation_response = navigate_to_destination(page, ctx.url)
        perform_preload(page)
        navigation_guards.raise_deferred_error!
        final_navigation_response = navigation_guards.latest_navigation_response || navigation_response
        navigation_guards.validate_final!(final_navigation_response)
        build_response(page, final_navigation_response)
      ensure
        page&.close
      end

      ##
      # @return [Puppeteer::Page]
      # @see https://yusukeiwaki.github.io/puppeteer-ruby-docs/Puppeteer/Page.html
      def new_page
        page = browser.new_page
        configure_page(page)
        navigation_guards.install!(page)
        page
      end

      ##
      # @param page [Puppeteer::Page]
      # @return [void]
      def configure_page(page)
        page.extra_http_headers = browser_headers
        page.default_navigation_timeout = navigation_timeout_ms
        page.default_timeout = navigation_timeout_ms
      end

      ##
      # @param page [Puppeteer::Page] browser page
      # @param url [Html2rss::Url] target URL
      # @return [Puppeteer::HTTPResponse, nil] the navigation response if one was produced
      def navigate_to_destination(page, url)
        navigation_guards.begin_navigation!
        page.goto(url, wait_until: 'networkidle0', referer:, timeout: navigation_timeout_ms).tap do
          navigation_guards.raise_deferred_error!
        end
      rescue StandardError
        navigation_guards.raise_deferred_error!

        raise
      end

      ##
      # @param page [Puppeteer::Page] browser page
      # @return [String] rendered HTML content
      def body(page) = page.content

      private

      attr_reader :ctx, :browser, :skip_request_resources, :referer, :navigation_guards

      def navigation_timeout_ms
        timeout = ctx.budget.remaining_timeout_seconds || ctx.policy.total_timeout_seconds
        raise RequestTimedOut, 'Request timed out' if timeout <= 0

        (timeout * 1000).to_i
      end

      def browser_headers
        ctx.headers.reject { |key, _| BROWSER_UNSAFE_HEADERS.include?(key.to_s.downcase) }
      end

      def build_response(page, navigation_response)
        Response.new(
          body: body(page),
          headers: navigation_response&.headers || {},
          url: response_url(navigation_response, ctx.url),
          status: navigation_response&.status
        )
      end

      def response_url(navigation_response, fallback_url)
        raw_url = navigation_response&.url || fallback_url.to_s
        Html2rss::Url.from_absolute(raw_url)
      end

      def perform_preload(page)
        preload_config = ctx.browserless_preload
        return unless preload_config

        wait_after(page, preload_config[:wait_after_ms])
        click_selectors(page, preload_config[:click_selectors]) if preload_config[:click_selectors]
        scroll_down(page, preload_config[:scroll_down]) if preload_config[:scroll_down]
        wait_after(page, preload_config[:wait_after_ms])
      end

      def wait_after(page, timeout_ms)
        return unless timeout_ms

        ctx.budget.consume_interaction!
        page.wait_for_timeout(timeout_ms)
      end

      def click_selectors(page, selectors)
        selectors.each { |selector_config| click_selector(page, selector_config) }
      end

      def scroll_down(page, config)
        iterations = config.fetch(:iterations, 1)
        wait_after_ms = config[:wait_after_ms]
        previous_height = nil

        iterations.times do
          updated_height = perform_scroll_iteration(page, wait_after_ms, previous_height)
          break unless updated_height

          previous_height = updated_height
        end
      end

      def click_selector(page, config)
        selector = config.fetch(:selector)
        max_clicks = config.fetch(:max_clicks, 1)
        wait_after_ms = config[:wait_after_ms]

        max_clicks.times do
          break unless (element = page.query_selector(selector))

          ctx.budget.consume_interaction!
          element.click
          wait_after(page, wait_after_ms)
        end
      end

      def perform_scroll_iteration(page, wait_after_ms, previous_height)
        ctx.budget.consume_interaction!
        page.evaluate('() => window.scrollTo(0, document.body.scrollHeight)')
        wait_after(page, wait_after_ms)

        current_height = page.evaluate('() => document.body.scrollHeight')
        return if previous_height && current_height <= previous_height

        current_height
      end
    end
  end
end
