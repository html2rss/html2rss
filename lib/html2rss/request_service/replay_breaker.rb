# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Process-local circuit breaker for cookie replay: after {MAX_BLOCKS} consecutive replay-then-block
    # outcomes for a jar key, replay stays off until the cookie TTL elapses.
    class ReplayBreaker
      # Consecutive blocked replays before the breaker opens.
      MAX_BLOCKS = Integer(ENV.fetch('BOTASAURUS_COOKIE_REPLAY_MAX_BLOCKS', 3))

      def initialize
        @state = {}
        @mutex = Mutex.new
      end

      ##
      # @param key [String] jar key
      # @return [Boolean] true while replay is suspended for the key
      def open?(key)
        @mutex.synchronize do
          open_until = @state[key]&.last
          next false unless open_until
          next true if now < open_until

          @state.delete(key)
          false
        end
      end

      ##
      # @param key [String] jar key
      # @param ttl [Numeric] seconds replay stays off once the breaker trips
      # @return [Boolean] true when this block tripped the breaker
      def record_block(key, ttl:)
        @mutex.synchronize do
          blocks = (@state[key]&.first || 0) + 1
          tripped = blocks >= MAX_BLOCKS
          @state[key] = [blocks, (now + ttl if tripped)]
          tripped
        end
      end

      ##
      # @param key [String] jar key
      # @return [void]
      def record_pass(key)
        @mutex.synchronize { @state.delete(key) }
      end

      private

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
