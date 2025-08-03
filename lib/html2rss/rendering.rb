# frozen_string_literal: true

module Html2rss
  # Namespace for HTML rendering logic, used to generate rich content such as
  # images, audio, video, or embedded documents for feed descriptions.
  #
  # @example
  #   Html2rss::Rendering::ImageRenderer.new(...).to_html
  #   Html2rss::Rendering::MediaRenderer.for(...)
  #
  # @see Html2rss::Rendering::DescriptionBuilder
  module Rendering
  end
end
