# frozen_string_literal: true

module Html2rss
  class AutoSource
    Assessment = Data.define(:surface_category, :articles_count, :admission_drops)

    ##
    # Cheap surface + admission facts shared by AutoFallback gates and EntryResolution probes.
    # Classifies only: one AutoSource run at a fixed limit, never a second extract job.
    class Assessment
      # Fixed AutoSource limit for the cheap article count.
      CHEAP_LIMIT = 10

      ##
      # @param response [Html2rss::RequestService::Response]
      # @param channel [Hash{Symbol => Object}] channel overrides; an explicit +:language+ wins over the page's
      # @param vocabulary [Html2rss::Vocabulary::Scope, nil] the page language's scope; resolved from
      #   +response+ and +channel+ when the caller has not already done so
      # @return [Assessment]
      def self.call(response:, channel: {}, vocabulary: nil)
        category = surface_category_for(response:)
        return new(surface_category: category, articles_count: 0, admission_drops: {}) \
          unless response.html_response?

        vocabulary ||= Vocabulary[Channel.language_for(response, channel)]
        clock = Clock.new(now: Time.now, time_zone: nil)
        source = AutoSource.new(response, DEFAULT_CONFIG.merge(limit: CHEAP_LIMIT), vocabulary:, clock:)
        new(surface_category: category, articles_count: source.articles.size,
            admission_drops: source.admission_drops)
      end

      ##
      # Surface class only — no AutoSource extract (for empty-extract error labels).
      #
      # @param response [Html2rss::RequestService::Response]
      # @return [Symbol]
      def self.surface_category_for(response:)
        return :unsupported_surface unless response.html_response?

        SurfaceCategory.classify(response.parsed_body, body: response.body)
      end

      ##
      # @return [Html2rss::AutoSource::SurfaceCategory]
      def category = SurfaceCategory[surface_category]

      ##
      # @return [Boolean]
      def weak? = category.weak?

      ##
      # @return [Boolean]
      def blocked? = category.blocked?

      ##
      # @return [Boolean]
      def listing_bonus? = category.listing_bonus?
    end
  end
end
