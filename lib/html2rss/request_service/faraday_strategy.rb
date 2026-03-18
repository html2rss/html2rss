# frozen_string_literal: true

require 'faraday'
require 'faraday/follow_redirects'
require 'faraday/gzip'

module Html2rss
  class RequestService
    ##
    # Strategy to use Faraday for the request.
    # @see https://rubygems.org/gems/faraday
    class FaradayStrategy < Strategy
      ##
      # NOTE: Unlike BrowserlessStrategy, Faraday does not expose the remote IP after connect.
      # SSRF protection here is pre-connection only (DNS resolution via Policy).
      # A DNS rebinding attack between resolution and connect cannot be caught at this layer.
      #
      # Executes a request with runtime policy enforcement.
      #
      # @return [Response] normalized request response
      def execute
        validate_request!

        response_guard = ResponseGuard.new(policy: ctx.policy)
        response = faraday_request
        response_guard.inspect_chunk!(total_bytes: response.body.bytesize, headers: response.headers)
        response_guard.inspect_body!(response.body)

        Response.new(body: response.body, headers: response.headers, url: response_url(response),
                     status: response.status)
      end

      private

      def validate_request!
        ctx.budget.consume!
        ctx.policy.validate_request!(url: ctx.url, origin_url: ctx.origin_url, relation: ctx.relation)
      end

      def faraday_request
        client.get do |req|
          apply_timeouts(req)
        end
      end

      def client
        @client ||= Faraday.new(url: ctx.url.to_s, headers: ctx.headers) do |faraday|
          faraday.use Faraday::FollowRedirects::Middleware, limit: ctx.policy.max_redirects, callback: redirect_callback
          faraday.request :gzip
          faraday.adapter Faraday.default_adapter
        end
      end

      def apply_timeouts(request)
        request.options.timeout = ctx.policy.total_timeout_seconds
        request.options.open_timeout = ctx.policy.connect_timeout_seconds
        request.options.read_timeout = ctx.policy.read_timeout_seconds
      end

      def response_url(response)
        return ctx.url unless (url = response.env&.url)

        Html2rss::Url.from_absolute(url.to_s)
      end

      def redirect_callback
        lambda do |old_env, new_env|
          from_url = normalize_url(old_env[:url])
          to_url = normalize_url(new_env[:url])
          ctx.policy.validate_redirect!(from_url:, to_url:, origin_url: ctx.origin_url, relation: ctx.relation)
        end
      end

      def normalize_url(url)
        Html2rss::Url.from_absolute(url.to_s)
      end
    end
  end
end
