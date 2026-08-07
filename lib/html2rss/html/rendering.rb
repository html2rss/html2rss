# frozen_string_literal: true

module Html2rss
  module Html
    # Namespace for HTML rendering logic, used to generate rich content such as
    # images, audio, video, or embedded documents for feed descriptions.
    #
    # @see Html2rss::Html::Rendering::DescriptionBuilder
    #
    # @example
    #   Html2rss::Html::Rendering::ImageRenderer.new(
    #     url: "https://example.com/image.jpg",
    #     title: "Example"
    #   ).to_html
    #
    # @example
    #   Html2rss::Html::Rendering::MediaRenderer.for(
    #     enclosure: nil,
    #     image: "https://example.com/image.jpg",
    #     title: "Example"
    #   )
    module Rendering
    end
  end
end
