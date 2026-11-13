# frozen_string_literal: true

module Html2rss
  module Syndication
    Feed = Data.define(:articles, :channel)

    ##
    # One parsed native feed ({Parser.parse}): its items as AutoSource article hashes and what it
    # states about its channel ({ChannelFacts}).
    #
    # @!attribute [r] articles
    #   @return [Array<Hash{Symbol => Object}>] article hashes (may be empty)
    # @!attribute [r] channel
    #   @return [ChannelFacts, nil] nil when the document is no RSS 2.0 or Atom feed or failed to parse
    class Feed
      # No feed read: no articles, no channel facts.
      NONE = new(articles: [].freeze, channel: nil)
    end
  end
end
