# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Commands the Puppeteer Browser to the website and builds the Response.
    class PuppetCommander # rubocop:disable Metrics/ClassLength
      DEFAULT_WAIT_FOR_NETWORK_IDLE_TIMEOUT = 5_000
      BROWSER_UNSAFE_HEADERS = %w[host connection content-length transfer-encoding].to_set.freeze

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
      end

      ##
      # Visits the request URL and normalizes the page into a response object.
      #
      # @return [Response] rendered page response
      def call
        page = new_page
        navigation_response = navigate_to_destination(page, ctx.url)
        perform_preload(page)
        final_navigation_response = latest_navigation_response || navigation_response
        validate_navigation_response!(final_navigation_response)
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
        configure_navigation_guards(page)
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
      # @param page [Puppeteer::Page]
      # @return [void]
      def configure_navigation_guards(page)
        page.request_interception = true
        page.on('request') do |request|
          handle_request(request)
        end
        page.on('response') { |response| handle_response(response) }
      end

      ##
      # @param page [Puppeteer::Page] browser page
      # @param url [Html2rss::Url] target URL
      # @return [Puppeteer::HTTPResponse, nil] the navigation response if one was produced
      def navigate_to_destination(page, url)
        @navigation_error = nil
        @latest_navigation_response = nil
        page.goto(url, wait_until: 'networkidle0', referer:, timeout: navigation_timeout_ms).tap do
          raise @navigation_error if @navigation_error
        end
      rescue StandardError
        raise @navigation_error if @navigation_error

        raise
      end

      ##
      # @param page [Puppeteer::Page] browser page
      # @return [String] rendered HTML content
      def body(page) = page.content

      private

      attr_reader :ctx, :browser, :skip_request_resources, :referer, :latest_navigation_response

      def navigation_timeout_ms
        ctx.policy.total_timeout_seconds * 1000
      end

      def browser_headers
        ctx.headers.reject { |key, _| BROWSER_UNSAFE_HEADERS.include?(key.to_s.downcase) }
      end

      def handle_request(request)
        validate_request!(request)

        skip_request_resources.member?(request.resource_type) ? request.abort : request.continue
      rescue Html2rss::Error => error
        store_navigation_error(error, navigation_request: request.navigation_request?)
        request.abort
      end

      def handle_response(response)
        @latest_navigation_response = response if response.request.navigation_request?
        validate_response!(response)
      rescue Html2rss::Error => error
        store_navigation_error(error, navigation_request: response.request.navigation_request?)
      end

      def validate_request!(request)
        validate_navigation_redirect_chain!(request)
        validate_navigation_target!(request)
      end

      def build_response(page, navigation_response)
        page_body = body(page)
        ResponseGuard.new(policy: ctx.policy).inspect_body!(page_body)

        Response.new(
          body: page_body,
          headers: navigation_response&.headers || {},
          url: response_url(navigation_response, ctx.url),
          status: navigation_response&.status
        )
      end

      def validate_navigation_response!(navigation_response)
        final_url = response_url(navigation_response, ctx.url)
        ctx.policy.validate_remote_ip!(ip: remote_ip(navigation_response), url: final_url)
      end

      def validate_response!(response)
        validate_navigation_response!(response)
      end

      def response_url(navigation_response, fallback_url)
        raw_url = navigation_response&.url || fallback_url.to_s
        Html2rss::Url.from_absolute(raw_url)
      end

      def remote_ip(navigation_response)
        navigation_response.remote_address&.ip
      end

      def request_chain(request)
        (request.redirect_chain + [request]).map { |entry| request_url(entry) }
      end

      def request_url(request)
        Html2rss::Url.from_absolute(request.url)
      end

      def validate_navigation_redirect_chain!(request)
        request_chain(request).each_cons(2) do |from_url, to_url|
          ctx.policy.validate_redirect!(from_url:, to_url:, origin_url: ctx.origin_url, relation: ctx.relation)
        end
      end

      def validate_navigation_target!(request)
        ctx.policy.validate_request!(url: request_url(request), origin_url: ctx.origin_url, relation: ctx.relation)
      end

      def store_navigation_error(error, navigation_request:)
        return unless navigation_request

        @navigation_error = error if @navigation_error.nil?
      end

      def perform_preload(page)
        preload_config = ctx.browserless_preload
        return unless preload_config

        wait_for_network_idle(page, preload_config[:wait_for_network_idle])
        click_selectors(page, preload_config[:click_selectors]) if preload_config[:click_selectors]
        scroll_down(page, preload_config[:scroll_down]) if preload_config[:scroll_down]
        wait_for_network_idle(page, preload_config[:wait_for_network_idle])
      end

      def wait_for_network_idle(page, config)
        return unless config

        timeout = config.fetch(:timeout_ms, DEFAULT_WAIT_FOR_NETWORK_IDLE_TIMEOUT)
        page.wait_for_timeout(timeout)
      end

      def click_selectors(page, selectors)
        selectors.each { |selector_config| click_selector(page, selector_config) }
      end

      def scroll_down(page, config)
        iterations = config.fetch(:iterations, 1)
        delay_ms = config.fetch(:delay_ms, 0)
        wait_config = config[:wait_for_network_idle]
        previous_height = nil

        iterations.times do
          updated_height = perform_scroll_iteration(page, wait_config, delay_ms, previous_height)
          break unless updated_height

          previous_height = updated_height
        end
      end

      def click_selector(page, config)
        selector = config.fetch(:selector)
        max_clicks = config.fetch(:max_clicks, 1)
        delay_ms = config.fetch(:delay_ms, 0)
        wait_config = config[:wait_for_network_idle]

        max_clicks.times do
          break unless (element = page.query_selector(selector))

          element.click
          wait_for_network_idle(page, wait_config)
          sleep(delay_ms / 1000.0) if delay_ms.positive?
        end
      end

      def perform_scroll_iteration(page, wait_config, delay_ms, previous_height)
        page.evaluate('() => window.scrollTo(0, document.body.scrollHeight)')
        wait_for_network_idle(page, wait_config)
        sleep(delay_ms / 1000.0) if delay_ms.positive?

        current_height = page.evaluate('() => document.body.scrollHeight')
        return if previous_height && current_height <= previous_height

        current_height
      end
    end
  end
end
