# frozen_string_literal: true

module Html2rss
  module FeedResolution
    ##
    # Decides whether an entry URL tournament should run after a weak extract.
    module Policy
      # Surfaces that warrant listing/feed resolution (not blocked).
      WEAK_SURFACES = %i[high_entropy_surface app_shell unsupported_surface].freeze
      # Minimum admitted articles before the entry URL is considered strong enough.
      ARTICLE_FLOOR = 3

      module_function

      ##
      # @param config [Html2rss::Config]
      # @param articles_count [Integer]
      # @param surface_category [Symbol, nil]
      # @return [Boolean]
      def resolve?(config:, articles_count:, surface_category:)
        return false unless eligible_config?(config)
        return false if surface_category == :blocked_surface

        articles_count.to_i < ARTICLE_FLOOR || WEAK_SURFACES.include?(surface_category)
      end

      def eligible_config?(config)
        return false unless config.auto_source
        return false if config.selectors

        config.auto_source.dig(:entry_resolution, :enabled) != false
      end
      module_function :eligible_config?
      private_class_method :eligible_config?
    end
  end
end
