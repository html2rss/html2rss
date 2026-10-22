# frozen_string_literal: true

require 'httpx'
require 'httpx/plugins/follow_redirects'
require 'httpx/plugins/callbacks'
require 'httpx/plugins/ssrf_filter'
require 'httpx/plugins/brotli'
require 'httpx/plugins/retries'

module Html2rss
  class RequestService
    ##
    # Strategy to use HTTPX for HTTP requests.
    # Provides native HTTP/2 with ALPN, built-in SSRF protection, streaming byte limits,
    # and redirect handling without monkey-patching.
    # rubocop:disable-next Metrics/ClassLength -- terminal redirect retry colocated with HTTPX transport
    class HttpxStrategy < Strategy
      # HTTPX default; kept explicit so ping reconnects cannot omit a bound.
      MAX_RETRIES = 3
      # Forces the selector timer retry path. Unset retry_after recurses in fetch_response;
      # combined with ping! on a reused closed selector that never decrements retries,
      # that overflows the stack and kills Falcon workers.
      RETRY_AFTER_SECONDS = 0.25
      # Base-session retries plugin defaults (stack-overflow guard for ping reconnects).
      # Per-request +session.with+ sets +max_retries: 0+; Ruby owns TimeoutError retries
      # against the monotonic deadline so HTTPX cannot stack read timeouts past the cap.
      # Do not reload +:fiber_concurrency+: a reused closed selector made +ping!+
      # skip decrementing retries and recurse until +SystemStackError+.
      #
      # @return [Hash{Symbol => Integer, Float}]
      RETRY_OPTIONS = { max_retries: MAX_RETRIES, retry_after: RETRY_AFTER_SECONDS }.freeze

      class << self
        # rubocop:disable ThreadSafety/ClassInstanceVariable
        # @return [HTTPX::Session]
        def base_session
          @base_session ||= HTTPX
                            .plugin(:follow_redirects)
                            .plugin(:callbacks)
                            .plugin(:brotli)
                            .plugin(:retries, **RETRY_OPTIONS)
        end

        # @return [HTTPX::Session]
        def base_ssrf_session
          @base_ssrf_session ||= base_session.plugin(:ssrf_filter)
        end
        # rubocop:enable ThreadSafety/ClassInstanceVariable
      end

      # Executes the request with runtime policy enforcement, returning the normalized response.
      #
      # @return [Response] normalized response
      def perform_execute
        deadline = request_deadline
        reset_redirect_tracking!
        raw_response = request_with_deadline_retries(deadline:)
        build_response(raw_response)
      end

      private

      # Caps one strategy execute (Ruby retries included) so a hanging :default tier
      # cannot consume the full shared auto-fallback budget.
      #
      # @return [Float] monotonic deadline
      def request_deadline
        budget_timeout = ctx.budget.effective_timeout_seconds(fallback: ctx.policy.total_timeout_seconds)
        Process.clock_gettime(Process::CLOCK_MONOTONIC) + [budget_timeout, attempt_timeout_ceiling].min
      end

      # @return [Float] connect + read ceiling for a single attempt
      def attempt_timeout_ceiling
        (ctx.policy.connect_timeout_seconds + ctx.policy.read_timeout_seconds).to_f
      end

      def reset_redirect_tracking!
        @last_redirect_to = nil
        @terminal_redirect_retried = false
        @request_url_override = nil
        @current_url = request_url
      end

      # Retries HTTPX timeouts in Ruby while the shared monotonic deadline has time left.
      # First try consumes the budget slot; retries do not.
      def request_with_deadline_retries(deadline:)
        state = { retries_remaining: MAX_RETRIES, consume_budget: true }

        begin
          request_with_terminal_redirect_retry(deadline:, consume_budget: state[:consume_budget])
        rescue HTTPX::TimeoutError => error
          prepare_deadline_retry!(deadline:, state:, error:)
          retry
        end
      end

      def prepare_deadline_retry!(deadline:, state:, error:)
        raise error if state[:retries_remaining].zero?

        remaining_timeout_seconds(deadline)
        state[:retries_remaining] -= 1
        state[:consume_budget] = false
        reset_redirect_tracking!
      end

      def request_with_terminal_redirect_retry(deadline:, consume_budget: true)
        raw_response = execute_http_request(deadline:, consume_budget:)
        return raw_response unless redirect_limit_reached?(raw_response)

        unless terminal_redirect_retryable?(raw_response)
          raise RedirectLimitReached, "Too many redirects (status #{raw_response.status})"
        end

        retry_from_terminal_redirect!(raw_response, deadline:)
      end

      def redirect_limit_reached?(response)
        return false unless response.is_a?(HTTPX::Response)
        return false if response.status == 304
        return false unless (300..399).cover?(response.status)

        location = response.headers['location']
        !location.to_s.strip.empty?
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

      def retry_from_terminal_redirect!(raw_response, deadline:)
        terminal_url = terminal_redirect_url(raw_response)
        @terminal_redirect_retried = true
        Log.debug("#{self.class}: redirect limit reached; retrying once from #{terminal_url}")
        begin_terminal_url_request!(terminal_url)
        new_response = execute_http_request(deadline:, consume_budget: false)
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

      def execute_http_request(deadline:, consume_budget: true)
        preflight!(consume_budget:)
        session = session_client(deadline)
        response = http_get(session)
        raise response.error if response.is_a?(HTTPX::ErrorResponse)

        response
      end

      # GET only. Overflow here is HTTPX retry recursion; the same error from
      # redirect handling or body decode must stay loud.
      def http_get(session)
        session.get(request_url.to_s, headers: ctx.headers)
      rescue SystemStackError
        raise HTTPX::ConnectionError, 'HTTPX retry recursion exhausted'
      end

      def session_client(deadline)
        session = ctx.policy.allow_private_networks? ? self.class.base_session : self.class.base_ssrf_session
        session.with(session_options(deadline))
      end

      # Plugin retries stay off per request; Ruby owns deadline-bounded TimeoutError retries.
      def session_options(deadline)
        remaining = remaining_timeout_seconds(deadline)
        {
          timeout: session_timeouts(remaining),
          max_redirects: ctx.policy.max_redirects,
          follow_insecure_redirects: false,
          max_response_body_size: ctx.policy.max_response_bytes,
          resolver_class: :system,
          redirect_on: redirect_callback,
          **RETRY_OPTIONS.merge(max_retries: 0)
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
        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise RequestTimedOut, 'Request timed out' if remaining <= 0

        remaining
      end

      def timeout_error?(error)
        error.is_a?(HTTPX::TimeoutError) || super
      end

      def ssrf_error?(error)
        error.is_a?(HTTPX::ServerSideRequestForgeryError) || super
      end

      def response_too_large_error?(error)
        (error.is_a?(HTTPX::Error) && error.message.include?('maximum response body size exceeded')) || super
      end

      def connection_error?(error)
        error.is_a?(HTTPX::ConnectionError) || error.is_a?(HTTPX::TLSError) || super
      end
    end
  end
end
