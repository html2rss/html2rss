# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Defines the guarded request interface for every strategy adapter.
    #
    # `#execute` always runs timeout check → budget/policy preflight → `#fetch`
    # → ResponseGuard postflight so new adapters cannot skip shared controls.
    class Strategy
      ##
      # @param ctx [Context] the context for the request
      def initialize(ctx)
        @ctx = ctx
      end

      ##
      # Executes the request through the shared preflight/postflight path.
      #
      # @return [Response] the response from the strategy
      # @raise [NotImplementedError] if the subclass does not implement `#fetch`
      def execute
        check_timeout!
        response = perform_execute
        postflight!(response)
        response
      rescue StandardError => error
        handle_error(error)
      end

      private

      # @return [Context] the context for the request
      attr_reader :ctx

      ##
      # Adapter hook: perform the preflight, fetch, and optional retry lifecycle.
      #
      # @return [Response] normalized response
      def perform_execute
        preflight!
        fetch
      end

      ##
      # Adapter hook: perform the transport-specific fetch after preflight.
      #
      # @return [Response] normalized response
      # @raise [NotImplementedError] when a subclass omits the hook
      def fetch
        raise NotImplementedError, 'Subclass must implement #fetch'
      end

      ##
      # Consumes a request slot and validates the destination before transport work.
      #
      # @param consume_budget [Boolean] whether to decrement the request budget
      # @return [void]
      def preflight!(consume_budget: true)
        return if skip_preflight?

        ctx.budget.consume! if consume_budget
        ctx.policy.validate_request!(url: ctx.url, origin_url: ctx.origin_url, relation: ctx.relation)
      end

      ##
      # Enforces response-size and blocked-surface checks after transport work.
      #
      # @param response [Response, nil] adapter response
      # @return [void]
      def postflight!(response)
        return if skip_postflight? || response.nil?

        ResponseGuard.new(policy: ctx.policy).inspect_body!(response.body)
      end

      ##
      # @return [Boolean] true when remote budget/policy preflight must be skipped
      def skip_preflight? = false

      ##
      # @return [Boolean] true when ResponseGuard postflight must be skipped
      def skip_postflight? = false

      def check_timeout!
        ctx.budget.effective_timeout_seconds(fallback: ctx.policy.total_timeout_seconds)
      rescue RequestTimedOut
        log_timeout!(reason: 'budget_exhausted')
        raise
      end

      # @param error [StandardError]
      # @return [void]
      # @raise [StandardError]
      # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength -- error translation dispatch
      def handle_error(error)
        if timeout_error?(error)
          log_timeout!(reason: 'transport')
          Log.debug("#{self.class}: transport timeout message=#{error.message}")
          raise RequestTimedOut, error.message
        elsif ssrf_error?(error)
          raise PrivateNetworkDenied, error.message
        elsif response_too_large_error?(error)
          raise ResponseTooLarge, "Response exceeded #{ctx.policy.max_response_bytes} bytes"
        elsif connection_error?(error)
          translate_connection_error(error)
        else
          raise error
        end
      end

      # @param reason [String] timeout classification (budget_exhausted / transport)
      # @return [void]
      # rubocop:disable-next Metrics/AbcSize -- structured timeout fields stay in one log line
      def log_timeout!(reason:)
        remaining = ctx.budget.remaining_timeout_seconds
        remaining_label = remaining.nil? ? 'untracked' : format('%.3f', remaining)
        detail = [
          "strategy=#{self.class.name}",
          "host=#{ctx.url.host}",
          "elapsed=#{format('%.3f', ctx.budget.elapsed_seconds)}s",
          "budget_remaining=#{remaining_label}",
          "reason=#{reason}"
        ]
        Log.info("#{self.class}: request timeout #{detail.join(' ')}")
      end

      # @param error [StandardError]
      # @return [void]
      # @raise [StandardError]
      def translate_connection_error(error)
        raise error
      end

      # @param error [StandardError]
      # @return [Boolean]
      def timeout_error?(error)
        error.is_a?(Timeout::Error)
      end

      # @param _error [StandardError]
      # @return [Boolean]
      def ssrf_error?(_error)
        false
      end

      # @param _error [StandardError]
      # @return [Boolean]
      def response_too_large_error?(_error)
        false
      end

      # @param error [StandardError]
      # @return [Boolean]
      def connection_error?(error)
        error.is_a?(SocketError) || error.is_a?(SystemCallError)
      end
    end
  end
end
