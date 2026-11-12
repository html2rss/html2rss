# frozen_string_literal: true

require 'dry-validation'

module Html2rss
  class Config
    # Scraper options are splatted into scraper constructors, so a key no scraper accepts is a
    # validation error. Key validation applies only when a schema is called directly, so the
    # auto-source contract keeps +scraper+ an open hash and {Validator} applies this one to it.
    # The raw values reach the scrapers, so this schema checks types without coercing them.
    AutoSourceScraperContract = Dry::Schema.JSON do # rubocop:disable Metrics/BlockLength
      config.validate_keys = true

      optional(:native_feed).hash do
        optional(:enabled).filled(:bool)
      end
      optional(:wordpress_api).hash do
        optional(:enabled).filled(:bool)
      end
      optional(:sitemap).hash do
        optional(:enabled).filled(:bool)
        optional(:min_priority).filled { int? | float? }
        optional(:max_age_days).filled(:integer, gt?: 0)
      end
      optional(:schema).hash do
        optional(:enabled).filled(:bool)
      end
      optional(:microdata).hash do
        optional(:enabled).filled(:bool)
      end
      optional(:microformats2).hash do
        optional(:enabled).filled(:bool)
      end
      optional(:json_state).hash do
        optional(:enabled).filled(:bool)
      end
      optional(:json_document).hash do
        optional(:enabled).filled(:bool)
      end
      optional(:xhr_articles).hash do
        optional(:enabled).filled(:bool)
      end
      optional(:meta_oembed).hash do
        optional(:enabled).filled(:bool)
      end
      optional(:semantic_html).hash do
        optional(:enabled).filled(:bool)
      end
      optional(:html).hash do
        optional(:enabled).filled(:bool)
        optional(:minimum_selector_frequency).filled(:integer, gt?: 0)
        optional(:use_top_selectors).filled(:integer, gt?: 0)
      end
    end

    # Runtime source of truth for validating auto-source config values.
    AutoSourceContract = Dry::Schema.Params do
      optional(:limit).filled(:integer, gt?: 0)
      optional(:entry_resolution).hash do
        optional(:enabled).filled(:bool)
        optional(:max_probes).filled(:integer, gt?: 0)
      end

      optional(:scraper).hash

      optional(:cleanup).hash do
        optional(:keep_different_domain).filled(:bool)
        optional(:keep_sponsored).filled(:bool)
      end
    end
  end
end
