# frozen_string_literal: true

module Html2rss
  # Namespace for feed format adapters (RSS 2.0 / JSON Feed 1.1).
  #
  # {FeedResult} constructs {Rss} / {JsonFeed} directly — there is no dispatcher
  # entrypoint on this module. Stylesheets are a scrape-time artifact carried on
  # FeedResult; +feed_url+ is a render-time JSON Feed-only option.
  #
  # Channel field projection:
  # - Rss: language, title, description, ttl, link, updated
  # - JsonFeed: title, home_page_url, description, language, icon, authors (+ feed_url)
  module FeedBuilder
  end
end
