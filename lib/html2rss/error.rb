# frozen_string_literal: true

module Html2rss
  # The Html2rss::Error base class.
  class Error < StandardError; end

  # Raised when auto fallback exhausts all concrete tiers and extractors find no feed items.
  class NoFeedItemsExtracted < Error
    # Categories that append shared surface guidance to the empty-feed message.
    SURFACE_HINT_CATEGORIES = %i[app_shell blocked_surface].freeze

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
      summaries = attempts.map do |attempt|
        details = attempt[:items_count].nil? ? "#{attempt[:error_class]} error" : "#{attempt[:items_count]} items"
        "#{attempt[:strategy]} (#{details})"
      end.join(', ')

      message = "No feed items extracted after auto fallback across strategies: #{summaries}. " \
                'Try a more specific listing URL or provide explicit selectors.'
      return message unless SURFACE_HINT_CATEGORIES.include?(surface_category)

      guidance = AutoSource::Scraper::NoScraperFound::CATEGORY_MESSAGES.fetch(surface_category)
      "#{message} #{guidance}"
    end
  end
end
