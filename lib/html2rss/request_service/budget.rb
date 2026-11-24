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
      # @param total_timeout_seconds [Integer] wall-clock timeout for the feed build
      def initialize(max_requests:, total_timeout_seconds:)
        Option.integer(:max_requests, max_requests, min: 1)

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
        @mutex.synchronize do
          raise RequestBudgetExceeded, 'Request budget exhausted' if @remaining_requests.zero?

          @remaining_requests -= 1
        end
      end

      ##
      # @return [Integer] HTTP request slots still available
      def remaining_requests
        @mutex.synchronize { @remaining_requests }
      end

      ##
      # @return [Float] the remaining timeout in seconds, never negative
      def remaining_timeout_seconds
        [@total_timeout_seconds - elapsed_seconds, 0.0].max
      end

      ##
      # @return [Float] seconds since this budget was created
      def elapsed_seconds
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time
      end

      ##
      # Resolves wall-clock seconds for the next adapter attempt.
      #
      # @return [Float] seconds available for this attempt
      # @raise [RequestTimedOut] when no time remains
      def effective_timeout_seconds
        timeout = remaining_timeout_seconds
        raise RequestTimedOut, 'Request timed out' if timeout.zero?

        timeout
      end
    end
  end
end
