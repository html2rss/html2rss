# frozen_string_literal: true

module Html2rss
  module Syndication
    ##
    # Shared path lexicon for syndication discovery and entry-resolution candidates.
    module CandidateCatalog
      # Common feed path suffixes probed after head +rel=alternate+ hints.
      FEED_PATHS = %w[
        /feed
        /feed.xml
        /rss
        /rss.xml
        /atom.xml
        /index.xml
        /news/rss
        /news/feed
        /blog/feed
        /blog/rss.xml
      ].freeze

      # HTML listing paths probed only by {FeedResolution::CandidateGenerator}.
      LISTING_PATHS = %w[/news /blog /releases /changelog /updates].freeze
    end
  end
end
