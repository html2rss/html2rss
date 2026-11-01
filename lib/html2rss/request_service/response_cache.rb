# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Bounded, thread-safe TTL cache for initial page fetches; install with
    # {RequestService.response_cache=}. Only successful (2xx) responses are stored, so a
    # block page or rate limit is never replayed.
    class ResponseCache
      # Default entry ceiling; oldest entries are evicted first.
      DEFAULT_MAX_ENTRIES = 64
      # Monotonic seconds source, immune to wall-clock jumps.
      MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      ##
      # @param ttl [Numeric] seconds an entry stays fresh
      # @param max_entries [Integer] maximum stored entries
      # @param clock [#call] monotonic seconds source (injectable for specs)
      def initialize(ttl:, max_entries: DEFAULT_MAX_ENTRIES, clock: MONOTONIC_CLOCK)
        @ttl = Option.integer(:ttl, ttl, min: 1)
        @max_entries = Option.integer(:max_entries, max_entries, min: 1)
        @clock = clock
        @entries = {}
        @mutex = Mutex.new
      end

      ##
      # @param key [Object] hashable cache key
      # @yieldreturn [Response] the freshly fetched response, built only on a miss
      # @return [Response] the cached or freshly built response
      def fetch(key)
        cached = lookup(key)
        return cached if cached

        yield.tap { |response| store(key, response) if cacheable?(response) }
      end

      private

      def lookup(key)
        @mutex.synchronize do
          expires_at, response = @entries[key]
          response if expires_at && expires_at > @clock.call
        end
      end

      def store(key, response)
        @mutex.synchronize do
          @entries.delete(key)
          @entries[key] = [@clock.call + @ttl, response]
          @entries.shift while @entries.size > @max_entries
        end
      end

      def cacheable?(response) = (200..299).cover?(response.status)
    end
  end
end
