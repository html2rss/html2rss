# frozen_string_literal: true

require 'digest'

module Html2rss
  class RequestService
    ##
    # In-process cookie jar for anti-bot clearance cookies returned by botasaurus-scrape-api.
    #
    # The scrape API is stateless, so html2rss owns reuse. Any object responding to
    # +fetch(key)+, +write(key, cookies, ttl:)+ and +evict(key)+ can replace this store via
    # {RequestService.cookie_store=} (e.g. Redis or a database in html2rss-web).
    #
    # Values are session credentials: never log, dump or persist them in feed config.
    class CookieStore
      # Seconds stored cookies are replayed (the API returns no expiry; 0 disables reuse).
      DEFAULT_TTL_SECONDS = Integer(ENV.fetch('BOTASAURUS_COOKIE_TTL_SECONDS', 1800))

      ##
      # Builds a jar key from everything a clearance cookie is bound to.
      # The digest keeps proxy credentials out of keys, logs and external stores.
      #
      # @param host [String] target host
      # @param scraper_base_url [String] scrape-api base URL
      # @param proxy [String, nil] egress proxy
      # @param user_agent [String, nil] browser user agent
      # @return [String] opaque jar key
      def self.key(host:, scraper_base_url:, proxy:, user_agent:)
        Digest::SHA256.hexdigest([host, scraper_base_url, proxy, user_agent].join("\0"))
      end

      def initialize
        @entries = {}
        @mutex = Mutex.new
      end

      ##
      # @param key [String] jar key
      # @return [Hash{String => String}] live cookies, {} when absent or expired
      def fetch(key)
        @mutex.synchronize do
          cookies, expires_at = @entries[key]
          next {} if cookies.nil?
          next cookies.dup if now < expires_at

          @entries.delete(key)
          {}
        end
      end

      ##
      # @param key [String] jar key
      # @param cookies [Hash{String => String}] cookies to keep
      # @param ttl [Numeric] seconds until expiry
      # @return [void]
      def write(key, cookies, ttl: DEFAULT_TTL_SECONDS)
        @mutex.synchronize do
          purge_expired
          @entries[key] = [cookies.dup.freeze, now + ttl]
        end
      end

      ##
      # @param key [String] jar key
      # @return [void]
      def evict(key)
        @mutex.synchronize { @entries.delete(key) }
      end

      private

      def purge_expired
        @entries.delete_if { |_key, (_cookies, expires_at)| expires_at <= now }
      end

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
