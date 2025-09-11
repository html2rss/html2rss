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

      # @return [Response]
      def call
        page = new_page
        url = ctx.url

        response = navigate_to_destination(page, url)

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
    end
  end
end
