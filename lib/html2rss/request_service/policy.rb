# frozen_string_literal: true

require 'ipaddr'
require 'resolv'
require 'socket'

module Html2rss
  class RequestService
    ##
    # Describes the runtime request envelope for a single feed build.
    class Policy # rubocop:disable Metrics/ClassLength
      LOCAL_HOSTS = %w[localhost localhost.localdomain metadata.google.internal].to_set.freeze
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

      DEFAULTS = {
        connect_timeout_seconds: 5,
        read_timeout_seconds: 10,
        total_timeout_seconds: 30,
        max_redirects: 3,
        max_response_bytes: 5_242_880,
        max_decompressed_bytes: 10_485_760,
        max_requests: 1,
        allow_private_networks: false,
        allow_cross_origin_followups: false
      }.freeze

      ##
      # @param connect_timeout_seconds [Integer] maximum connection setup time
      # @param read_timeout_seconds [Integer] maximum read stall time
      # @param total_timeout_seconds [Integer] maximum total request time
      # @param max_redirects [Integer] maximum redirect count
      # @param max_response_bytes [Integer] maximum streamed response bytes
      # @param max_decompressed_bytes [Integer] maximum final body size
      # @param max_requests [Integer] maximum requests per feed build
      # @param allow_private_networks [Boolean] whether private network targets are allowed
      # @param allow_cross_origin_followups [Boolean] whether follow-up requests may leave the origin host
      # @param resolver [#each_address] DNS resolver used for hostname classification
      def initialize(connect_timeout_seconds: DEFAULTS[:connect_timeout_seconds], # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
                     read_timeout_seconds: DEFAULTS[:read_timeout_seconds],
                     total_timeout_seconds: DEFAULTS[:total_timeout_seconds],
                     max_redirects: DEFAULTS[:max_redirects],
                     max_response_bytes: DEFAULTS[:max_response_bytes],
                     max_decompressed_bytes: DEFAULTS[:max_decompressed_bytes],
                     max_requests: DEFAULTS[:max_requests],
                     allow_private_networks: DEFAULTS[:allow_private_networks],
                     allow_cross_origin_followups: DEFAULTS[:allow_cross_origin_followups],
                     resolver: Socket)
        @connect_timeout_seconds = validate_positive_integer!(:connect_timeout_seconds, connect_timeout_seconds)
        @read_timeout_seconds = validate_positive_integer!(:read_timeout_seconds, read_timeout_seconds)
        @total_timeout_seconds = validate_positive_integer!(:total_timeout_seconds, total_timeout_seconds)
        @max_redirects = validate_non_negative_integer!(:max_redirects, max_redirects)
        @max_response_bytes = validate_positive_integer!(:max_response_bytes, max_response_bytes)
        @max_decompressed_bytes = validate_positive_integer!(:max_decompressed_bytes, max_decompressed_bytes)
        @max_requests = validate_positive_integer!(:max_requests, max_requests)
        @allow_private_networks = allow_private_networks ? true : false
        @allow_cross_origin_followups = allow_cross_origin_followups ? true : false
        @resolver = resolver
        freeze
      end

      attr_reader :connect_timeout_seconds,
                  :read_timeout_seconds,
                  :total_timeout_seconds,
                  :max_redirects,
                  :max_response_bytes,
                  :max_decompressed_bytes,
                  :max_requests

      ##
      # @return [Boolean] whether private network targets may be requested
      def allow_private_networks?
        @allow_private_networks
      end

      ##
      # @return [Boolean] whether follow-up requests may leave the initial origin
      def allow_cross_origin_followups?
        @allow_cross_origin_followups
      end

      ##
      # Returns the default request policy.
      #
      # @return [Policy] a default, frozen policy instance
      # rubocop:disable Layout/ClassStructure
      def self.default
        DEFAULT_POLICY
      end
      # rubocop:enable Layout/ClassStructure

      ##
      # Validates whether a request target is permitted for the given context.
      #
      # @param url [Html2rss::Url] destination URL
      # @param origin_url [Html2rss::Url] initial URL of the feed build
      # @param relation [Symbol] logical reason for the request
      # @return [void]
      # @raise [CrossOriginFollowUpDenied] if a follow-up leaves the origin host
      # @raise [PrivateNetworkDenied] if the target resolves to a private address
      def validate_request!(url:, origin_url:, relation:)
        enforce_same_origin!(url, origin_url, relation)
        enforce_public_network!(url)
      end

      ##
      # Validates a redirect hop before it is followed.
      #
      # @param from_url [Html2rss::Url] URL that produced the redirect
      # @param to_url [Html2rss::Url] redirect destination
      # @param origin_url [Html2rss::Url] initial URL of the feed build
      # @param relation [Symbol] logical reason for the request
      # @return [void]
      # @raise [UnsupportedUrlScheme] if the redirect downgrades from HTTPS to HTTP
      def validate_redirect!(from_url:, to_url:, origin_url:, relation:)
        if from_url.scheme == 'https' && to_url.scheme == 'http'
          raise UnsupportedUrlScheme, 'Redirect downgraded from https to http'
        end

        validate_request!(url: to_url, origin_url:, relation:)
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
        return unless parsed_ip && blocked_ip?(parsed_ip)

        raise PrivateNetworkDenied, "Private network target denied for #{url}"
      end

      private

      attr_reader :resolver

      def validate_positive_integer!(name, value)
        raise ArgumentError, "#{name} must be positive" unless value.is_a?(Integer) && value.positive?

        value
      end

      def validate_non_negative_integer!(name, value)
        raise ArgumentError, "#{name} must be non-negative" unless value.is_a?(Integer) && !value.negative?

        value
      end

      def enforce_same_origin!(url, origin_url, relation)
        return if relation == :initial || allow_cross_origin_followups?
        return if comparable_origin(url) == comparable_origin(origin_url)

        raise CrossOriginFollowUpDenied, "Cross-origin follow-up denied for #{url}"
      end

      def comparable_origin(url)
        [url.host, normalized_port(url)]
      end

      def normalized_port(url)
        return url.port if url.port

        url.scheme == 'https' ? 443 : 80
      end

      def enforce_public_network!(url)
        host = url.host
        return if allow_private_networks?
        return unless blocked_host?(host) || blocked_resolved_address?(host)

        raise PrivateNetworkDenied, "Private network target denied for #{url}"
      end

      def blocked_host?(host)
        LOCAL_HOSTS.include?(host.to_s.downcase)
      end

      def blocked_resolved_address?(host)
        literal = parse_ip(host)
        return blocked_ip?(literal) if literal

        if resolver.respond_to?(:each_address)
          blocked_address_from_each_address?(host)
        else
          blocked_address_from_getaddrinfo?(host)
        end
      rescue Resolv::ResolvError, SocketError, SystemCallError
        false
      end

      def blocked_address_from_each_address?(host)
        resolver.each_address(host) do |address|
          parsed = parse_ip(address)
          return true if parsed && blocked_ip?(parsed)
        end

        false
      end

      def blocked_address_from_getaddrinfo?(host)
        resolver.getaddrinfo(host, nil).any? do |entry|
          (parsed = parse_ip(entry[3])) && blocked_ip?(parsed)
        end
      end

      def parse_ip(value)
        IPAddr.new(value)
      rescue IPAddr::InvalidAddressError
        nil
      end

      def blocked_ip?(address)
        BLOCKED_IP_RANGES.any? { |range| range.include?(address) }
      end
    end

    Policy::DEFAULT_POLICY = Policy.new
  end
end
