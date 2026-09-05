# frozen_string_literal: true

require 'httpx'
require 'httpx/plugins/follow_redirects'
require 'httpx/plugins/callbacks'
require 'httpx/plugins/ssrf_filter'

module Html2rss
  class RequestService
    ##
    # Strategy to use HTTPX for HTTP requests.
    # Provides native HTTP/2 with ALPN, built-in SSRF protection, streaming byte limits,
    # and redirect handling without monkey-patching.
    # rubocop:disable-next Metrics/ClassLength -- terminal redirect retry colocated with HTTPX transport
    class HttpxStrategy < Strategy
      CONNECTION_HEADERS = %w[connection keep-alive proxy-connection transfer-encoding upgrade].freeze

      ##
      # @return [ResponseGuard]
      attr_reader :response_guard

      # Executes the request with runtime policy enforcement, returning the normalized response.
      #
      # @return [Response] normalized response
      def perform_execute
        deadline = request_deadline
        @response_guard = ResponseGuard.new(policy: ctx.policy)
        reset_redirect_tracking!
        raw_response = request_with_terminal_redirect_retry(response_guard, deadline:)
        build_response(raw_response)
      end

      private

      def request_deadline
        monotonic_now + ctx.budget.effective_timeout_seconds(fallback: ctx.policy.total_timeout_seconds)
      end

      def reset_redirect_tracking!
        @last_redirect_to = nil
        @terminal_redirect_retried = false
        @request_url_override = nil
        @current_url = request_url
      end

      def request_with_terminal_redirect_retry(response_guard, deadline:)
        raw_response = execute_http_request(response_guard, deadline:)
        return raw_response unless redirect_limit_reached?(raw_response)

        unless terminal_redirect_retryable?(raw_response)
          raise RedirectLimitReached, "Too many redirects (status #{raw_response.status})"
        end

        retry_from_terminal_redirect!(raw_response, response_guard, deadline:)
      end

      def redirect_limit_reached?(response)
        return false unless response.is_a?(HTTPX::Response)

        (300..399).cover?(response.status)
      end

      def terminal_redirect_url(raw_response)
        location = raw_response.headers['location']
        if location && !location.empty?
          base = raw_response.uri || request_url
          return normalize_url(URI.join(base.to_s, location))
        end

        @last_redirect_to
      end

      def terminal_redirect_retryable?(raw_response)
        return false if @terminal_redirect_retried

        target = terminal_redirect_url(raw_response)
        target && target.to_s != request_url.to_s
      end

      def retry_from_terminal_redirect!(raw_response, response_guard, deadline:)
        terminal_url = terminal_redirect_url(raw_response)
        @terminal_redirect_retried = true
        Log.debug("#{self.class}: redirect limit reached; retrying once from #{terminal_url}")
        begin_terminal_url_request!(terminal_url)
        new_response = execute_http_request(response_guard, deadline:, consume_budget: false)
        if redirect_limit_reached?(new_response)
          raise RedirectLimitReached, "Too many redirects (status #{new_response.status})"
        end

        new_response
      end

      def begin_terminal_url_request!(terminal_url)
        ctx.policy.validate_request!(url: terminal_url, origin_url: ctx.origin_url, relation: ctx.relation)
        @request_url_override = terminal_url
        @last_redirect_to = nil
        @current_url = terminal_url
      end

      def request_url
        @request_url_override || ctx.url
      end

      def execute_http_request(response_guard, deadline:, consume_budget: true)
        preflight!(consume_budget:)
        session = build_session(response_guard, deadline:)
        response = session.get(request_url.to_s, headers: sanitized_headers)
        raise response.error if response.is_a?(HTTPX::ErrorResponse)

        response
      end

      def sanitized_headers
        ctx.headers.reject { |k, _| CONNECTION_HEADERS.include?(k.to_s.downcase) }
      end

      def build_session(response_guard, deadline:)
        session = session_client(deadline)
        streamed_bytes = 0
        session = session.on_response_started do |_req, res|
          response_guard.inspect_chunk!(total_bytes: 0, headers: res.headers.to_h)
        end
        session.on_response_body_chunk do |_req, res, chunk|
          streamed_bytes += chunk.bytesize
          response_guard.inspect_chunk!(total_bytes: streamed_bytes, headers: res.headers.to_h)
        end
      end

      def session_client(deadline)
        session = HTTPX.plugin(:follow_redirects).plugin(:callbacks)
        session = session.plugin(:ssrf_filter) unless ctx.policy.allow_private_networks?
        session.with(session_options(deadline))
      end

      def session_options(deadline)
        remaining = remaining_timeout_seconds(deadline)
        {
          timeout: session_timeouts(remaining),
          max_redirects: ctx.policy.max_redirects,
          follow_insecure_redirects: false,
          max_response_body_size: ctx.policy.max_response_bytes,
          resolver_class: :system,
          redirect_on: redirect_callback
        }
      end

      def session_timeouts(remaining)
        {
          connect_timeout: [ctx.policy.connect_timeout_seconds, remaining].min,
          read_timeout: [ctx.policy.read_timeout_seconds, remaining].min,
          operation_timeout: remaining,
          request_timeout: remaining,
          total_request_timeout: remaining
        }
      end

      def redirect_callback
        lambda do |redirect_uri|
          to_url = normalize_url(redirect_uri)
          from_url = @current_url
          @last_redirect_to = to_url
          ctx.policy.validate_redirect!(from_url:, to_url:, origin_url: ctx.origin_url, relation: ctx.relation)
          @current_url = to_url
          true
        end
      end

      def build_response(response)
        headers = response.headers.to_h
        Response.new(
          body: CompressedBody.decode(response.body.to_s, headers:),
          headers:,
          url: response_url(response),
          status: response.status
        )
      end

      def response_url(response)
        return ctx.url unless (uri = response.uri)

        Html2rss::Url.from_absolute(uri.to_s)
      end

      def normalize_url(url)
        Html2rss::Url.from_absolute(url.to_s)
      end

      def remaining_timeout_seconds(deadline)
        remaining = deadline - monotonic_now
        raise RequestTimedOut, 'Request timed out' if remaining <= 0

        remaining
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
