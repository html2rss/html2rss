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
      # @param articles [Array<Html2rss::Article>] typed extract results (count derived)
      # @param surface_category [Html2rss::SurfaceCategory, Symbol, nil]
      # @return [Boolean]
      def resolve?(config:, articles:, surface_category:)
        return false unless eligible_config?(config)

        category = SurfaceCategory.coerce(surface_category)
        return false if category.blocked?

        articles = Array(articles)
        articles.size < ARTICLE_FLOOR || category.weak? || native_feed_majority?(articles)
      end

      def eligible_config?(config)
        return false unless config.auto_source
        return false if config.selectors

        Options.from_auto_source(config.auto_source).enabled?
      end
      module_function :eligible_config?
      private_class_method :eligible_config?

      def native_feed_majority?(articles)
        return false if articles.empty?

        native = articles.count { |article| article.scraper == AutoSource::Scraper::NativeFeed }
        native * 2 >= articles.size
      end
      module_function :native_feed_majority?
      private_class_method :native_feed_majority?
    end
  end
end
