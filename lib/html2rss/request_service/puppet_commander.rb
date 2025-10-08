# frozen_string_literal: true

require 'set' # rubocop:disable Lint/RedundantRequireStatement

module Html2rss
  class RequestService
    ##
    # Commands the Puppeteer Browser to the website and builds the Response.
    class PuppetCommander
      DEFAULT_WAIT_FOR_NETWORK_IDLE_TIMEOUT = 5_000

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

      # @return [Response]
      def call
        page = new_page
        url = ctx.url

        response = navigate_to_destination(page, url)
        perform_preload(page)

        Response.new(body: body(page), headers: response.headers, url:)
      ensure
        page&.close
      end

      ##
      # @return [Puppeteer::Page]
      # @see https://yusukeiwaki.github.io/puppeteer-ruby-docs/Puppeteer/Page.html
      def new_page
        page = browser.new_page
        page.extra_http_headers = ctx.headers

        return page if skip_request_resources.empty?

        page.request_interception = true
        page.on('request') do |request|
          skip_request_resources.member?(request.resource_type) ? request.abort : request.continue
        end

        page
      end

      def navigate_to_destination(page, url)
        page.goto(url, wait_until: 'networkidle0', referer:)
      end

      def body(page) = page.content

      private

      attr_reader :ctx, :browser, :skip_request_resources, :referer

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
