# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Tracks how many outbound requests a single feed build may still perform.
    class Budget
      ##
      ##
      # @param max_requests [Integer] the maximum number of requests allowed
      # @param total_timeout_seconds [Integer, nil] the total timeout for the feed build
      def initialize(max_requests:, total_timeout_seconds: nil)
        unless max_requests.is_a?(Integer) && max_requests.positive?
          raise ArgumentError, 'max_requests must be positive'
        end

        @remaining = max_requests
        @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @total_timeout_seconds = total_timeout_seconds
        @mutex = Mutex.new
      end

      ##
      # Consumes one request from the budget.
      #
      # @return [Integer] remaining request count after consumption
      # @raise [RequestBudgetExceeded] if no requests remain
      def consume!
        @mutex.synchronize do
          raise RequestBudgetExceeded, 'Request budget exhausted' if @remaining.zero?

          @remaining -= 1
        end
      end

      ##
      # @return [Integer] requests still available
      def remaining
        @mutex.synchronize { @remaining }
      end

      ##
      # @return [Float, nil] the remaining timeout in seconds, or nil if not tracked
      def remaining_timeout_seconds
        return unless @total_timeout_seconds

        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
        remaining = @total_timeout_seconds - elapsed
        [remaining, 0.0].max
      end
    end
  end
end
