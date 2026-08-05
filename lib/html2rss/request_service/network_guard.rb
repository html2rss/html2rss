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
      LOCAL_HOSTS = %w[localhost localhost.localdomain metadata.google.internal].to_set.freeze
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
        IPAddr.new('ff00::/8')
      ].freeze

      ##
      # @param allow_private_networks [Boolean] whether private network targets are allowed
      # @param resolver [#each_address, #getaddrinfo] DNS resolver used for hostname classification
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
        return unless blocked_host?(host) || resolved_ip_addresses(host).any? { |address| blocked_ip?(address) }

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
        return if ip.nil? || ip.empty?

        parsed_ip = parse_ip(ip)
        raise PrivateNetworkDenied, "Remote IP could not be validated for #{url}" unless parsed_ip
        return unless blocked_ip?(parsed_ip)

        raise PrivateNetworkDenied, "Private network target denied for #{url}"
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

        if resolver.respond_to?(:each_address)
          addresses_from_each_address(host)
        else
          addresses_from_getaddrinfo(host)
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

      def blocked_ip?(address)
        BLOCKED_IP_RANGES.any? { |range| range.include?(address) }
      end
    end
  end
end
