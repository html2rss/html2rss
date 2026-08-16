# frozen_string_literal: true

module Html2rss
  # The Html2rss::Error base class.
  class Error < StandardError; end

  # Raised when auto fallback exhausts all concrete tiers and extractors find no feed items.
  class NoFeedItemsExtracted < Error
    # Categories that append shared surface guidance to the empty-feed message.
    SURFACE_HINT_CATEGORIES = %i[app_shell blocked_surface high_entropy_surface].freeze

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
        details = attempt[:items_count].nil? ? "#{attempt[:error_class]} error" : "#{attempt[:items_count]} items"
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
