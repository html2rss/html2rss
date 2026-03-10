# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Commands the Puppeteer Browser to the website and builds the Response.
    class PuppetCommander
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
        validate_navigation_response!(navigation_response)
        build_response(page, navigation_response)
      ensure
        page&.close
      end

      ##
      # @return [Puppeteer::Page]
      # @see https://yusukeiwaki.github.io/puppeteer-ruby-docs/Puppeteer/Page.html
      def new_page
        page = browser.new_page
        configure_page(page)
        configure_request_interception(page)
        page
      end

      ##
      # @param page [Puppeteer::Page]
      # @return [void]
      def configure_page(page)
        page.extra_http_headers = ctx.headers
        page.default_navigation_timeout = navigation_timeout_ms
        page.default_timeout = navigation_timeout_ms
      end

      ##
      # @param page [Puppeteer::Page]
      # @return [void]
      def configure_request_interception(page)
        return if skip_request_resources.empty?

        page.request_interception = true
        page.on('request') do |request|
          skip_request_resources.member?(request.resource_type) ? request.abort : request.continue
        end
      end

      ##
      # @param page [Puppeteer::Page] browser page
      # @param url [Html2rss::Url] target URL
      # @return [Puppeteer::HTTPResponse, nil] the navigation response if one was produced
      def navigate_to_destination(page, url)
        page.goto(url, wait_until: 'networkidle0', referer:, timeout: navigation_timeout_ms)
      end

      ##
      # @param page [Puppeteer::Page] browser page
      # @return [String] rendered HTML content
      def body(page) = page.content

      private

      attr_reader :ctx, :browser, :skip_request_resources, :referer

      def navigation_timeout_ms
        ctx.policy.total_timeout_seconds * 1000
      end

      def build_response(page, navigation_response)
        page_body = body(page)
        ResponseGuard.new(policy: ctx.policy).inspect_body!(page_body)

        Response.new(
          body: page_body,
          headers: navigation_response&.headers || {},
          url: response_url(navigation_response, ctx.url)
        )
      end

      def validate_navigation_response!(navigation_response)
        return unless navigation_response

        final_url = response_url(navigation_response, ctx.url)
        validate_redirect!(final_url)
        ctx.policy.validate_remote_ip!(ip: remote_ip(navigation_response), url: final_url)
      end

      def response_url(navigation_response, fallback_url)
        raw_url = navigation_response&.url || fallback_url.to_s
        Html2rss::Url.from_relative(raw_url, raw_url)
      end

      def validate_redirect!(final_url)
        ctx.policy.validate_redirect!(
          from_url: ctx.url,
          to_url: final_url,
          origin_url: ctx.origin_url,
          relation: ctx.relation
        )
      end

      def remote_ip(navigation_response)
        navigation_response.remote_address&.ip
      end
    end
  end
end
