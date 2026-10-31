# frozen_string_literal: true

module Html2rss
  class RequestService
    ##
    # One host/egress-scoped view onto the {CookieStore}: replay, refresh and evict with count-only telemetry.
    # Cookie names and values are session credentials and never reach logs.
    class CookieJar
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
      def stored
        cookies = store.fetch(key)
        log('replay', cookies.size) if cookies.any?
        cookies
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

      def log(action, count)
        Log.info({ event_name: 'botasaurus.cookie_jar', action:, host:, cookie_count: count }.to_json)
      end
    end
  end
end
