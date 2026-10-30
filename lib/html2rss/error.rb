# frozen_string_literal: true

module Html2rss
  # The Html2rss::Error base class.
  class Error < StandardError
    # Upstream transport_meta keys promoted into error diagnostics.
    TRANSPORT_META_KEYS = %i[request_id strategy_used render_ms error_category timeout_phase].freeze

    class << self
      ##
      # Builds a sparse diagnostics hash from attempt hashes and optional error metadata.
      #
      # @param attempts [Array<Hash>, nil] tier attempt diagnostics
      # @param transport_meta [Hash, nil] direct error transport metadata
      # @param timeout_phase [String, nil] timeout stage when known
      # @param surface_category [Symbol, nil] page surface classification when known
      # @return [Hash{Symbol => Object}]
      def diagnostics_from_attempts(attempts, transport_meta: nil, timeout_phase: nil, surface_category: nil)
        list = Array(attempts)
        meta = list.filter_map { |item| item[:transport_meta] || item['transport_meta'] }.last || transport_meta
        fields = extract_transport_fields(meta)
        fields[:timeout_phase] ||= timeout_phase
        fields[:surface_category] = surface_category
        { strategy_attempts: (list if list.any?), **fields }.compact
      end

      private

      def extract_transport_fields(meta)
        return {} unless meta

        TRANSPORT_META_KEYS.to_h { |key| [key, meta[key] || meta[key.to_s]] }
      end
    end

    # @return [Array<Hash{Symbol => Object}>, nil] tier attempt diagnostics when set by AutoFallback
    attr_accessor :attempts

    # @return [Hash{String => Object}, nil] allowlisted upstream transport telemetry when attached
    attr_accessor :transport_meta

    # @return [String, nil] scrape-api timeout stage when known (overridden by RequestTimedOut)
    def timeout_phase; end

    # @return [Symbol, nil] surface classification when known (overridden by NoFeedItemsExtracted)
    def surface_category; end

    ##
    # Sparse telemetry hash for observability consumers.
    #
    # @return [Hash{Symbol => Object}]
    def diagnostics
      self.class.diagnostics_from_attempts(
        attempts,
        transport_meta:,
        timeout_phase:,
        surface_category:
      )
    end
  end

  # Raised when a caller-supplied option value is malformed or out of range.
  class InvalidOption < Error; end

  # Raised when auto fallback exhausts all concrete tiers and extractors find no feed items.
  class NoFeedItemsExtracted < Error
    # Categories that append shared surface guidance to the empty-feed message.
    SURFACE_HINT_CATEGORIES = Set[:app_shell, :blocked_surface, :high_entropy_surface].freeze

    ##
    # @param attempts [Array<Hash{Symbol => Object}>] tier attempt diagnostics
    # @param surface_category [Symbol, nil] optional Scraper surface classification
    def initialize(attempts:, surface_category: nil)
      @attempts = attempts
      @surface_category = surface_category
      super(build_message)
    end

    # @return [Array<Hash{Symbol => Object}>] tier attempt diagnostics
    attr_reader :attempts

    # @return [Symbol, nil] surface classification when a response body was available
    attr_reader :surface_category

    private

    def build_message
      [base_message, surface_guidance, botasaurus_guidance].compact.join(' ')
    end

    def base_message
      summaries = attempts.map do |attempt|
        count = attempt[:items_count]
        details = count.nil? ? "#{attempt[:error_class]} error" : "#{count} items"
        "#{attempt[:strategy]} (#{details})"
      end.join(', ')

      "No feed items extracted after auto fallback across strategies: #{summaries}. " \
        'Try a more specific listing URL or provide explicit selectors.'
    end

    def surface_guidance
      return unless SURFACE_HINT_CATEGORIES.include?(surface_category)

      AutoSource::Scraper::NoScraperFound::CATEGORY_MESSAGES.fetch(surface_category)
    end

    def botasaurus_guidance
      return unless botasaurus_configuration_error_attempt?
      return if surface_guidance&.include?('BOTASAURUS_SCRAPER_URL')

      RequestService::BotasaurusConfigurationError::EMPTY_FEED_HINT
    end

    def botasaurus_configuration_error_attempt?
      error_name = RequestService::BotasaurusConfigurationError.name
      attempts.any? { |attempt| attempt[:error_class] == error_name }
    end
  end
end
