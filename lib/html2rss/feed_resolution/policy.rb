# frozen_string_literal: true

module Html2rss
  module FeedResolution
    ##
    # Decides whether an entry URL tournament should run after a weak extract.
    module Policy
      # Minimum admitted articles before the entry URL is considered strong enough.
      ARTICLE_FLOOR = 3

      module_function

      ##
      # @param config [Html2rss::Config]
      # @param articles_count [Integer]
      # @param surface_category [Html2rss::SurfaceCategory, Symbol, nil]
      # @return [Boolean]
      def resolve?(config:, articles_count:, surface_category:)
        return false unless eligible_config?(config)

        category = SurfaceCategory.coerce(surface_category)
        return false if category.blocked?

        articles_count.to_i < ARTICLE_FLOOR || category.weak?
      end

      def eligible_config?(config)
        return false unless config.auto_source
        return false if config.selectors

        Options.from_auto_source(config.auto_source).enabled?
      end
      module_function :eligible_config?
      private_class_method :eligible_config?
    end
  end
end
