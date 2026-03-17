# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Commands the Puppeteer Browser to the website and builds the Response.
    class PuppetCommander # rubocop:disable Metrics/ClassLength
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

      attr_reader :ctx, :browser, :skip_request_resources, :referer

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
          url: response_url(navigation_response, ctx.url)
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
    end
  end
end
