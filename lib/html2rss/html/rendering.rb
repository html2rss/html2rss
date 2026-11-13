# frozen_string_literal: true

module Html2rss
  module Html
    # Namespace for HTML rendering logic: the feed item description and its one media element
    # (an image, audio or video player).
    #
    # @see Html2rss::Html::Rendering::DescriptionBuilder
    #
    # @example
    #   Html2rss::Html::Rendering::ImageRenderer.new(
    #     url: "https://example.com/image.jpg",
    #     title: "Example"
    #   ).to_html
    module Rendering
    end
  end
end
