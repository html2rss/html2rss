# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # One host/egress-scoped view onto the {CookieStore}: replay, refresh and evict with count-only telemetry.
    # Cookie names and values are session credentials and never reach logs.
    class CookieJar
      # Share of replayable requests that deliberately skip replay, so the pass-rate effect stays measurable.
      HOLDOUT_RATE = Float(ENV.fetch('BOTASAURUS_COOKIE_HOLDOUT_RATE', 0.1))
      # Shared across jars so blocks accumulate per key within the process.
      BREAKER = ReplayBreaker.new

      ##
      # @param host [String] target host
      # @param scraper_base_url [String] scrape-api base URL
      # @param proxy [String, nil] egress proxy
      # @param user_agent [String, nil] browser user agent
      # @param store [#fetch, #write, #evict] the configured cookie store
      def initialize(host:, scraper_base_url:, proxy:, user_agent:, store: RequestService.cookie_store)
        @store = store
        @host = host
        @key = CookieStore.key(host:, scraper_base_url:, proxy:, user_agent:)
      end

      # @return [Hash{String => String}] live stored cookies ({} when none)
      def stored = store.fetch(key)

      ##
      # @param stored [Hash{String => String}] cookies in the jar
      # @return [Boolean] whether to replay them (not when empty, the breaker is open, or in the holdout)
      def replayable?(stored)
        return false if stored.empty?

        reason = skip_reason
        log(reason, 0) if reason
        reason.nil?
      end

      ##
      # Records what a replay led to: a pass resets the breaker; a block evicts the jar and counts toward it.
      #
      # @param outcome [Symbol] +:pass+ or +:block+
      # @param stored [Hash{String => String}] cookies that were replayed
      # @return [void]
      def replayed(outcome, stored)
        log("replay_#{outcome}", stored.size)
        return BREAKER.record_pass(key) if outcome == :pass

        evict(stored)
        log('breaker_open', 0) if BREAKER.record_block(key, ttl: CookieStore::DEFAULT_TTL_SECONDS)
      end

      ##
      # @param stored [Hash{String => String}] cookies that were replayed
      # @param earned [Hash{String => String}] cookies returned by the scrape
      # @return [void]
      def refresh(stored, earned)
        ttl = CookieStore::DEFAULT_TTL_SECONDS
        return if earned.empty? || ttl <= 0

        store.write(key, stored.merge(earned), ttl:)
        log('refresh', earned.size)
      end

      ##
      # @param stored [Hash{String => String}] cookies that were rejected
      # @return [void]
      def evict(stored)
        store.evict(key)
        log('evict', stored.size)
      end

      private

      attr_reader :store, :key, :host

      def skip_reason
        return 'breaker_open' if BREAKER.open?(key)

        'holdout' if rand < HOLDOUT_RATE
      end

      def log(action, count)
        Log.info({ event_name: 'botasaurus.cookie_jar', action:, host:, cookie_count: count }.to_json)
      end
    end
  end
end
