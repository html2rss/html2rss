# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Defines the guarded request interface for every strategy adapter.
    #
    # `#execute` always runs timeout check → budget/policy preflight → `#fetch`
    # → body guard postflight so new adapters cannot skip shared controls.
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
      def execute
        check_timeout!
        response = perform_execute
        postflight!(response)
        response
      rescue Html2rss::ContractError
        raise
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
      # Spends the request slot, then validates the destination before transport work.
      # Adapters that retry charge once here or via {#charge_budget!} and re-validate per attempt.
      #
      # @return [void]
      def preflight!
        charge_budget!
        validate_request!
      end

      ##
      # Spends one request budget slot for the logical request.
      #
      # @return [void]
      def charge_budget!
        ctx.budget.consume! unless skip_preflight?
      end

      ##
      # Validates the current destination against the request policy; spends nothing.
      #
      # @return [void]
      def validate_request!
        return if skip_preflight?

        ctx.policy.validate_request!(
          url: ctx.url, origin_url: ctx.origin_url, relation: ctx.relation, advertisement: ctx.advertisement
        )
      end

      ##
      # Enforces response-size and blocked-surface checks after transport work.
      #
      # @param response [Response, nil] adapter response
      # @return [void]
      def postflight!(response)
        return if skip_postflight?

        guard_body!(response)
      end

      ##
      # Rejects bodies above the decompressed limit or matching an anti-bot interstitial signature.
      #
      # @param response [Response] final response
      # @return [void]
      # @raise [ResponseTooLarge] if the body exceeds the configured limit
      # @raise [BlockedSurfaceDetected] if the body matches a known interstitial signature
      def guard_body!(response)
        body = response.body.to_s
        limit = ctx.policy.max_decompressed_bytes_for(response)
        raise ResponseTooLarge, "Response exceeded #{limit} bytes" if body.bytesize > limit

        signature = BlockedSurface.interstitial_signature_for(body)
        raise BlockedSurfaceDetected, signature.fetch(:message) if signature
      end

      ##
      # @return [Boolean] true when remote budget/policy preflight must be skipped
      def skip_preflight? = false

      ##
      # @return [Boolean] true when the adapter guards bodies itself or reads no remote body
      def skip_postflight? = false

      def check_timeout!
        ctx.budget.effective_timeout_seconds
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
          raise ResponseTooLarge, "Response exceeded #{ctx.policy.max_stream_bytes} bytes"
        elsif connection_error?(error)
          translate_connection_error(error)
        else
          raise error
        end
      end

      # @param reason [String] timeout classification (budget_exhausted / transport)
      # @return [void]
      # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength -- structured timeout fields stay in one log line
      def log_timeout!(reason:)
        remaining_label = format('%.3f', ctx.budget.remaining_timeout_seconds)
        host = ctx.url.host
        detail = [
          "strategy=#{self.class.name}",
          "host=#{host}",
          "elapsed=#{format('%.3f', ctx.budget.elapsed_seconds)}s",
          "budget_remaining=#{remaining_label}",
          "reason=#{reason}"
        ]
        Log.event(
          :info, 'request_service.timeout',
          host:,
          strategy: self.class.name,
          message: "#{self.class}: request timeout #{detail.join(' ')}"
        )
      end

      # @param error [StandardError]
      # @return [void]
      # @raise [ConnectionFailed]
      def translate_connection_error(error)
        raise ConnectionFailed, error.message
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
