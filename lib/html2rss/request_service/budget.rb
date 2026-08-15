# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Tracks HTTP request slots and wall-clock deadline for one feed build.
    #
    # HTTP fetches consume request slots. Deadline remains on `#remaining_timeout_seconds`.
    class Budget
      ##
      # @param max_requests [Integer] maximum HTTP request slots
      # @param total_timeout_seconds [Integer, nil] wall-clock timeout for the feed build
      def initialize(max_requests:, total_timeout_seconds: nil)
        validate_slot_limits!(max_requests:)

        @remaining_requests = max_requests
        @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @total_timeout_seconds = total_timeout_seconds
        @mutex = Mutex.new
      end

      ##
      # Consumes one HTTP request slot.
      #
      # @return [Integer] remaining request slots after consumption
      # @raise [RequestBudgetExceeded] if no request slots remain
      def consume!
        consume_request!
      end

      ##
      # Consumes one HTTP request slot.
      #
      # @return [Integer] remaining request slots after consumption
      # @raise [RequestBudgetExceeded] if no request slots remain
      def consume_request!
        @mutex.synchronize do
          raise RequestBudgetExceeded, 'Request budget exhausted' if @remaining_requests.zero?

          @remaining_requests -= 1
        end
      end

      ##
      # @return [Integer] HTTP request slots still available
      def remaining
        remaining_requests
      end

      ##
      # @return [Integer] HTTP request slots still available
      def remaining_requests
        @mutex.synchronize { @remaining_requests }
      end

      ##
      # @return [Float, nil] the remaining timeout in seconds, or nil if not tracked
      def remaining_timeout_seconds
        return unless @total_timeout_seconds

        remaining = @total_timeout_seconds - elapsed_seconds
        [remaining, 0.0].max
      end

      ##
      # @return [Float] seconds since this budget was created
      def elapsed_seconds
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
      end

      ##
      # Resolves wall-clock seconds for the next adapter attempt.
      #
      # Prefers the tracked deadline remainder; falls back to the policy total when
      # this Budget was constructed without a timeout (common in unit tests).
      #
      # @param fallback [Numeric] policy total timeout when remaining is untracked
      # @return [Float] seconds available for this attempt
      # @raise [RequestTimedOut] when no time remains
      def effective_timeout_seconds(fallback:)
        timeout = remaining_timeout_seconds || fallback
        raise RequestTimedOut, 'Request timed out' if timeout <= 0

        timeout.to_f
      end

      ##
      # @param fallback [Numeric] policy total timeout when remaining is untracked
      # @return [Integer] milliseconds available for this attempt
      # @raise [RequestTimedOut] when no time remains
      def effective_timeout_ms(fallback:)
        (effective_timeout_seconds(fallback:) * 1000).to_i
      end

      private

      def validate_slot_limits!(max_requests:)
        return if max_requests.is_a?(Integer) && max_requests.positive?

        raise ArgumentError, 'max_requests must be positive'
      end
    end
  end
end
