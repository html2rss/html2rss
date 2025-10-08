# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Configuration
      DEFAULT_CONFIG = {
        scraper: {
          schema: {
            enabled: true
          },
          json_state: {
            enabled: true
          },
          semantic_html: {
            enabled: true
          },
          html: {
            enabled: true,
            minimum_selector_frequency: Scraper::Html::DEFAULT_MINIMUM_SELECTOR_FREQUENCY,
            use_top_selectors: Scraper::Html::DEFAULT_USE_TOP_SELECTORS
          },
          rss_feed_detector: {
            enabled: true
          }
        },
        pagination: {
          enabled: true,
          max_pages: 1,
          selectors: [
            'link[rel="next"]',
            'a[rel="next"]',
            '.pagination a[rel~="next"]',
            '.pagination a.next',
            '.pagination a[href]'
          ]
        },
        cleanup: Cleanup::DEFAULT_CONFIG
      }.freeze

      ENABLED_ONLY_SCHEMA = proc do
        optional(:enabled).filled(:bool)
      end

      SCRAPER_SCHEMA = proc do
        optional(:schema).hash(&ENABLED_ONLY_SCHEMA)
        optional(:json_state).hash(&ENABLED_ONLY_SCHEMA)
        optional(:semantic_html).hash(&ENABLED_ONLY_SCHEMA)
        optional(:html).hash do
          optional(:enabled).filled(:bool)
          optional(:minimum_selector_frequency).filled(:integer, gt?: 0)
          optional(:use_top_selectors).filled(:integer, gt?: 0)
        end
        optional(:rss_feed_detector).hash(&ENABLED_ONLY_SCHEMA)
      end

      PAGINATION_SCHEMA = proc do
        optional(:enabled).filled(:bool)
        optional(:max_pages).filled(:integer, gt?: 0)
        optional(:selectors).array(:string)
      end

      CLEANUP_SCHEMA = proc do
        optional(:keep_different_domain).filled(:bool)
        optional(:min_words_title).filled(:integer, gt?: 0)
      end

      SCHEMA = Dry::Schema.Params do
        optional(:scraper).hash(&SCRAPER_SCHEMA)
        optional(:pagination).hash(&PAGINATION_SCHEMA)
        optional(:cleanup).hash(&CLEANUP_SCHEMA)
      end
    end
  end
end
