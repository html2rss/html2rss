# frozen_string_literal: true

require 'httpx'
require 'httpx/plugins/ssrf_filter'

module Html2rss
  class RequestService
    ##
    # HTTPX plugin layered on +:ssrf_filter+ (HTTPX 1.9.x, which offers no per-address predicate).
    # +ssrf_filter+ denies the whole NAT64 prefix; here it is released via +safe_private_ranges+
    # only together with a per-address check by {NetworkGuard} (embedded IPv4) and HTTPX's own
    # IPv4 list on the embedded address. Either denying an address drops it (fail closed).
    # Loading +:ssrf_filter+ first as a dependency keeps this module ahead of it in the
    # ancestors; a spec pins that order.
    module NetworkGuardFilter
      # Strict guard instance: the plugin only exists on the SSRF-protected session.
      GUARD = NetworkGuard.new(allow_private_networks: false)

      class << self
        # @param klass [Class] HTTPX session class being extended
        # @return [void]
        def load_dependencies(klass)
          klass.plugin(:ssrf_filter)
        end

        # @param options [HTTPX::Options] session options
        # @return [HTTPX::Options] options with the NAT64 prefix released to {NetworkGuard}
        def extra_options(options)
          options.merge(safe_private_ranges: [NetworkGuard::NAT64_PREFIX])
        end

        # @param ipaddr [IPAddr]
        # @return [Boolean] true when the guard or HTTPX's IPv4 list denies the address
        def denied?(ipaddr)
          return true if GUARD.blocked_ip?(ipaddr)

          embedded = GUARD.embedded_ipv4(ipaddr)
          !embedded.nil? && HTTPX::Plugins::SsrfFilter.unsafe_ip_address?(embedded)
        end
      end

      # Connection hooks.
      module ConnectionMethods
        # @param addrs [Array<#address>] resolved entries
        # @return [void]
        # @raise [HTTPX::ServerSideRequestForgeryError] when no entry is allowed
        def addresses=(addrs)
          super(addrs.reject { |entry| NetworkGuardFilter.denied?(entry.address) })
        end
      end
    end
  end
end
