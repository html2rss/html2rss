# frozen_string_literal: true

require 'dry-validation'

module Html2rss
  class Config
    # Runtime source of truth for validating auto-source config values.
    AutoSourceContract = Dry::Schema.Params do # rubocop:disable Metrics/BlockLength
      optional(:limit).filled(:integer, gt?: 0)
      optional(:entry_resolution).hash do
        optional(:enabled).filled(:bool)
        optional(:max_probes).filled(:integer, gt?: 0)
      end

      optional(:scraper).hash do # rubocop:disable Metrics/BlockLength
        optional(:native_feed).hash do
          optional(:enabled).filled(:bool)
        end
        optional(:wordpress_api).hash do
          optional(:enabled).filled(:bool)
        end
        optional(:sitemap).hash do
          optional(:enabled).filled(:bool)
          optional(:min_priority).filled(:float)
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
        optional(:xhr_articles).hash do
          optional(:enabled).filled(:bool)
        end
        optional(:meta_oembed).hash do
          optional(:enabled).filled(:bool)
        end
        optional(:semantic_html).hash do
          optional(:enabled).filled(:bool)
          optional(:fallback_anchorless).filled(:bool)
        end
        optional(:html).hash do
          optional(:enabled).filled(:bool)
          optional(:minimum_selector_frequency).filled(:integer, gt?: 0)
          optional(:use_top_selectors).filled(:integer, gt?: 0)
          optional(:fallback_anchorless).filled(:bool)
        end
      end

      optional(:cleanup).hash do
        optional(:keep_different_domain).filled(:bool)
      end
    end
  end
end
