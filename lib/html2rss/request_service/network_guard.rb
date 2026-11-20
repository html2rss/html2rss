# frozen_string_literal: true

require 'ipaddr'
require 'resolv'
require 'socket'

module Html2rss
  class RequestService
    ##
    # Enforces public-network reachability for request targets and remote IPs.
    #
    # Owns DNS resolution, host denylist, and blocked IP ranges. Callers go through
    # {Policy} so SSRF/origin rules stay single-homed on the public façade.
    class NetworkGuard
      # Hostnames treated as local/private surfaces.
      LOCAL_HOSTS = Set['localhost', 'localhost.localdomain', 'metadata.google.internal'].freeze
      # IP ranges blocked when private networks are disabled.
      BLOCKED_IP_RANGES = [
        IPAddr.new('0.0.0.0/8'),
        IPAddr.new('10.0.0.0/8'),
        IPAddr.new('127.0.0.0/8'),
        IPAddr.new('169.254.0.0/16'),
        IPAddr.new('172.16.0.0/12'),
        IPAddr.new('192.168.0.0/16'),
        IPAddr.new('224.0.0.0/4'),
        IPAddr.new('::/128'),
        IPAddr.new('::1/128'),
        IPAddr.new('fe80::/10'),
        IPAddr.new('fc00::/7'),
        IPAddr.new('ff00::/8'),
        # RFC 8215 local-use NAT64 prefix: not globally reachable.
        IPAddr.new('64:ff9b:1::/48'),
        # Teredo (RFC 4380): client address is obfuscated, so the whole prefix is denied.
        IPAddr.new('2001::/32')
      ].freeze
      # RFC 6052 well-known NAT64 prefix; the last 32 bits embed an IPv4 address.
      NAT64_PREFIX = IPAddr.new('64:ff9b::/96')
      # 6to4 (RFC 3056); bits 16..47 embed an IPv4 address. Decoded only to deny private embeds;
      # the HTTPX filter still denies all of 2002::/16 at connect.
      SIX_TO_FOUR_PREFIX = IPAddr.new('2002::/16')

      ##
      # @param allow_private_networks [Boolean] whether private network targets are allowed
      # @param resolver [Socket, Resolv] DNS resolver used for hostname classification.
      #   +Socket+ (the default) uses +getaddrinfo+; any other resolver is Resolv-shaped
      #   and must implement +each_address+.
      def initialize(allow_private_networks:, resolver: Socket)
        @allow_private_networks = allow_private_networks ? true : false
        @resolver = resolver
        freeze
      end

      ##
      # Rejects URLs whose host is denylisted or resolves to a blocked address.
      #
      # @param url [Html2rss::Url] destination URL
      # @return [void]
      # @raise [PrivateNetworkDenied] if the target resolves to a private address
      def enforce_public_network!(url)
        host = url.host
        return if allow_private_networks?
        raise PrivateNetworkDenied, "Private network target denied for #{url}" if blocked_host?(host)

        addresses = resolved_ip_addresses(host)
        return unless addresses.empty? || addresses.any? { |address| blocked_ip?(address) }

        raise PrivateNetworkDenied, "Private network target denied for #{url}"
      end

      ##
      # Validates the resolved remote IP for a completed request.
      #
      # @param ip [String, nil] remote IP address reported by the client
      # @param url [Html2rss::Url] URL associated with the response
      # @return [void]
      # @raise [PrivateNetworkDenied] if the response came from a blocked address
      def validate_remote_ip!(ip:, url:)
        return if allow_private_networks?

        parsed_ip = parse_ip(ip.to_s)
        raise PrivateNetworkDenied, "Remote IP could not be validated for #{url}" unless parsed_ip
        return unless blocked_ip?(parsed_ip)

        raise PrivateNetworkDenied, "Private network target denied for #{url}"
      end

      ##
      # Single owner of the IP allow/deny decision. IPv6 forms that embed an IPv4 address
      # (IPv4-mapped, NAT64 64:ff9b::/96, 6to4) are allowed only if the embedded IPv4 is.
      #
      # @param address [IPAddr] resolved or remote address
      # @return [Boolean] true when the address must be denied
      def blocked_ip?(address)
        native = address.native
        return true if BLOCKED_IP_RANGES.any? { |range| range.include?(native) }

        embedded = embedded_ipv4(native)
        !embedded.nil? && blocked_ip?(embedded)
      end

      ##
      # @param address [IPAddr] native (non-mapped) address
      # @return [IPAddr, nil] the IPv4 embedded in a NAT64 or 6to4 address, else nil
      def embedded_ipv4(address)
        if NAT64_PREFIX.include?(address)
          IPAddr.new_ntoh(address.hton[12..])
        elsif SIX_TO_FOUR_PREFIX.include?(address)
          IPAddr.new_ntoh(address.hton[2, 4])
        end
      end

      private

      attr_reader :resolver

      def allow_private_networks?
        @allow_private_networks
      end

      def blocked_host?(host)
        LOCAL_HOSTS.include?(host.to_s.downcase)
      end

      def resolved_ip_addresses(host)
        literal = parse_ip(host)
        return [literal] if literal

        if resolver == Socket
          addresses_from_getaddrinfo(host)
        else
          addresses_from_each_address(host)
        end
      rescue Resolv::ResolvError, SocketError, SystemCallError
        []
      end

      def addresses_from_each_address(host)
        [].tap do |addresses|
          resolver.each_address(host) do |address|
            parsed = parse_ip(address)
            addresses << parsed if parsed
          end
        end
      end

      def addresses_from_getaddrinfo(host)
        resolver.getaddrinfo(host, nil).filter_map do |entry|
          parse_ip(entry[3])
        end
      end

      def parse_ip(value)
        IPAddr.new(value)
      rescue IPAddr::AddressFamilyError, IPAddr::InvalidAddressError
        nil
      end
    end
  end
end
