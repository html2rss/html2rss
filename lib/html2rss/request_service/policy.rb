# frozen_string_literal: true

require 'socket'

module Html2rss
  class RequestService
    ##
    # Enforcer for the runtime request envelope of a single feed build.
    #
    # Public façade for request limits, same-origin/follow-up rules, and
    # network reachability. DNS/host/IP enforcement lives on {NetworkGuard}.
    class Policy
      # Hard ceiling for configured max_requests during a feed build.
      MAX_REQUESTS_CEILING = 10

      # Default policy values used when request controls are not explicitly set.
      DEFAULTS = {
        connect_timeout_seconds: Integer(ENV.fetch('HTML2RSS_CONNECT_TIMEOUT_SECONDS', 5)),
        read_timeout_seconds: Integer(ENV.fetch('HTML2RSS_READ_TIMEOUT_SECONDS', 10)),
        total_timeout_seconds: Integer(ENV.fetch('HTML2RSS_TOTAL_TIMEOUT_SECONDS', 30)),
        max_redirects: 5,
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
        @max_requests = [validate_positive_integer!(:max_requests, max_requests), MAX_REQUESTS_CEILING].min
        @allow_private_networks = allow_private_networks ? true : false
        @allow_cross_origin_followups = allow_cross_origin_followups ? true : false
        @network_guard = NetworkGuard.new(allow_private_networks: @allow_private_networks, resolver:)
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
        new
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
        network_guard.enforce_public_network!(url)
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
        network_guard.validate_remote_ip!(ip:, url:)
      end

      private

      attr_reader :network_guard

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

        enforce_follow_up_scheme!(url, origin_url)
        return if comparable_origin(url) == comparable_origin(origin_url)

        raise CrossOriginFollowUpDenied, "Cross-origin follow-up denied for #{url}"
      end

      def enforce_follow_up_scheme!(url, origin_url)
        return unless origin_url.scheme == 'https' && url.scheme == 'http'

        raise UnsupportedUrlScheme, "Follow-up downgraded from https to http for #{url}"
      end

      def comparable_origin(url)
        [url.host, normalized_port(url)]
      end

      def normalized_port(url)
        return url.port if url.port

        url.scheme == 'https' ? 443 : 80
      end
    end

    # Shared immutable policy instance used for default request execution.
    Policy::DEFAULT_POLICY = Policy.new
  end
end
