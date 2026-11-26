# frozen_string_literal: true

module Html2rss
  module FeedBuilder
    # Namespace for feed item rendering logic: the feed item description and its one media element
    # (an image, audio or video player).
    #
    # @see Html2rss::FeedBuilder::Rendering::DescriptionBuilder
    #
    # @example
    #   Html2rss::FeedBuilder::Rendering::Media.image(
    #     url: "https://example.com/image.jpg",
    #     title: "Example"
    #   )
    module Rendering
    end
  end
end
