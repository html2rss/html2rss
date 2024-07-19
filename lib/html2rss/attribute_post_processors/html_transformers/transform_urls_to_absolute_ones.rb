# frozen_string_literal: true

module Html2rss
  module AttributePostProcessors
    module HtmlTransformers
      ##
      # Transformer that converts relative URLs to absolute URLs within specified HTML elements.
      class TransformUrlsToAbsoluteOnes
        URL_ELEMENTS_WITH_URL_ATTRIBUTE = { 'a' => :href, 'img' => :src }.freeze

        def initialize(channel_url)
          @channel_url = channel_url
        end

        ##
        # Transforms URLs to absolute ones.
        def call(node_name:, node:, **_env)
          return unless URL_ELEMENTS_WITH_URL_ATTRIBUTE.key?(node_name)

          url_attribute = URL_ELEMENTS_WITH_URL_ATTRIBUTE[node_name]
          url = node[url_attribute]
          node[url_attribute] = Html2rss::Utils.build_absolute_url_from_relative(url, @channel_url)
        end
      end
    end
  end
end
