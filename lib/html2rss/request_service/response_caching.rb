# frozen_string_literal: true

require 'digest'

module Html2rss
  class RequestService
    ##
    # Opt-in reuse of initial page fetches, e.g. while a person iterates on selectors for one page.
    # Extended onto {RequestService}; the cache is consulted only for +relation == :initial+ requests,
    # follow-ups always hit the network.
    #
    # The key is a SHA256 digest of the URL, strategy, headers, request options and the policy fields
    # that shape a response, so credentials never reach the cache and a response fetched under a
    # permissive {Policy} is never served to a stricter one. Cookie-store state is not part of the key.
    module ResponseCaching
      # Mutex guarding the process-wide response cache reference.
      RESPONSE_CACHE_MUTEX = Mutex.new
      # Fiber-storage key for the active {#observe_cache_hits} collector.
      CACHE_HITS_KEY = :html2rss_cache_hits
      private_constant :RESPONSE_CACHE_MUTEX, :CACHE_HITS_KEY

      # @param cache [#fetch, nil] receives +fetch(key) { response }+ and returns the cached or freshly
      #   built {Response} (tagged with {Response#cache_age} on a hit), e.g. {ResponseCache};
      #   +nil+ (the default) disables caching. A raising block must not be cached.
      # @return [void]
      def response_cache=(cache)
        RESPONSE_CACHE_MUTEX.synchronize { @response_cache = cache }
      end

      # @return [#fetch, nil] the configured initial-response cache, if any
      def response_cache
        RESPONSE_CACHE_MUTEX.synchronize { @response_cache }
      end

      # Runs the block and reports the cache ages of every initial fetch it served from {#response_cache},
      # including fetches on threads the block spawns (fiber storage is inherited by reference).
      #
      # @yieldreturn [Object] the block's result
      # @return [Array(Object, Array<Integer>)] the block's result and the served cache ages in seconds
      def observe_cache_hits
        hits = Fiber[CACHE_HITS_KEY] = Queue.new
        result = yield
        [result, Array.new(hits.size) { hits.pop }]
      ensure
        Fiber[CACHE_HITS_KEY] = nil
      end

      private

      ##
      # Runs +fetch+ directly, or through {#response_cache} for initial requests.
      # Callers always receive their own {Response} so parsed documents are never shared.
      # @param ctx [Context] the request context
      # @param strategy [Symbol] the resolved strategy name
      # @yieldreturn [Response] the freshly fetched response
      # @return [Response]
      def fetch_initial_through_cache(ctx, strategy, &)
        cache = response_cache
        return yield unless cache && ctx.relation == :initial

        cache.fetch(response_cache_key(ctx, strategy), &).replica.tap { |response| record_cache_hit(response) }
      end

      def record_cache_hit(response)
        Fiber[CACHE_HITS_KEY]&.push(response.cache_age) if response.cache_age
      end

      def response_cache_key(ctx, strategy)
        parts = [ctx.url.to_s, strategy, ctx.headers.sort, ctx.request, ctx.policy.cache_key]
        Digest::SHA256.hexdigest(parts.inspect)
      end
    end
  end
end
