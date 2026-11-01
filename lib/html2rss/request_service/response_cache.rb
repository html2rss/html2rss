# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # Bounded, thread-safe TTL cache for initial page fetches; install with
    # {RequestService.response_cache=}. Only successful (2xx) responses are stored, so a
    # block page or rate limit is never replayed. Hits are returned tagged with their
    # {Response#cache_age}; memory is capped in body bytes as well as entries.
    class ResponseCache
      # Default entry ceiling; oldest entries are evicted first.
      DEFAULT_MAX_ENTRIES = 32
      # Default body-byte budget across all entries.
      DEFAULT_MAX_BYTES = 32 * 1024 * 1024
      # Monotonic seconds source, immune to wall-clock jumps.
      MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      Entry = Data.define(:stored_at, :response, :bytes)
      private_constant :Entry

      # @return [Integer] seconds an entry stays fresh
      attr_reader :ttl

      ##
      # @param ttl [Integer] seconds an entry stays fresh
      # @param max_entries [Integer] maximum stored entries
      # @param max_bytes [Integer] maximum summed body bytes
      # @param clock [#call] monotonic seconds source (injectable for specs)
      def initialize(ttl:, max_entries: DEFAULT_MAX_ENTRIES, max_bytes: DEFAULT_MAX_BYTES, clock: MONOTONIC_CLOCK)
        @ttl = Option.integer(:ttl, ttl, min: 1)
        @max_entries = Option.integer(:max_entries, max_entries, min: 1)
        @max_bytes = Option.integer(:max_bytes, max_bytes, min: 1)
        @clock = clock
        @entries = {}
        @bytes = 0
        @mutex = Mutex.new
        @flight_done = ConditionVariable.new
        @inflight = Set.new
      end

      ##
      # Concurrent callers missing the same key share one fetch: the first builds the response while
      # the others wait, then each is served its own replica. A raising or uncacheable fetch is not
      # stored; waiters then retry in turn so none is left blocked.
      # @param key [Object] hashable cache key
      # @yieldreturn [Response] the freshly fetched response, built only on a miss
      # @return [Response] a cache-aged replica on a hit, otherwise the freshly built response
      def fetch(key, &)
        cached = claim(key)
        return cached if cached

        lead(key, &)
      end

      private

      # Returns a fresh replica, or nil after registering the caller as the key's fetcher.
      def claim(key)
        @mutex.synchronize do
          loop do
            hit = lookup(key)
            break hit if hit
            break @inflight.add(key) && nil unless @inflight.include?(key)

            @flight_done.wait(@mutex)
          end
        end
      end

      def lead(key)
        yield.tap { |response| store(key, response) if cacheable?(response) }
      ensure
        @mutex.synchronize do
          @inflight.delete(key)
          @flight_done.broadcast
        end
      end

      # Callers must hold @mutex.
      def lookup(key)
        entry = @entries[key]
        age = entry && (@clock.call - entry.stored_at)
        entry.response.replica(cache_age: age.floor) if age && age < @ttl
      end

      def store(key, response)
        @mutex.synchronize do
          evict(key)
          bytes = response.body.bytesize
          @entries[key] = Entry.new(stored_at: @clock.call, response:, bytes:)
          @bytes += bytes
          evict_oldest while @entries.size > @max_entries || @bytes > @max_bytes
        end
      end

      def evict(key)
        @bytes -= @entries.delete(key)&.bytes.to_i
      end

      def evict_oldest
        _key, entry = @entries.shift
        @bytes -= entry.bytes
      end

      def cacheable?(response)
        (200..299).cover?(response.status) && response.body.bytesize <= @max_bytes
      end
    end
  end
end
