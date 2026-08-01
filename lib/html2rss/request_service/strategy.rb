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
        run_guarded_fetch
      end

      private

      # @return [Context] the context for the request
      attr_reader :ctx

      ##
      # Adapter hook: perform the transport-specific fetch after preflight.
      #
      # @return [Response] normalized response
      # @raise [NotImplementedError] when a subclass omits the hook
      def fetch
        raise NotImplementedError, 'Subclass must implement #fetch'
      end

      ##
      # Runs budget/policy preflight, adapter fetch, and ResponseGuard postflight.
      #
      # @param consume_budget [Boolean] whether this attempt consumes a request slot
      # @return [Response] guarded response
      def run_guarded_fetch(consume_budget: true)
        preflight!(consume_budget:)
        response = fetch
        postflight!(response)
        response
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
        remaining = ctx.budget.remaining_timeout_seconds
        raise RequestTimedOut, 'Request timed out' if remaining && remaining <= 0
      end
    end
  end
end
