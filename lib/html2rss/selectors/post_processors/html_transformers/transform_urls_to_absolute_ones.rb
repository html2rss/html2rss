# frozen_string_literal: true

module Html2rss
  class Selectors
    module PostProcessors
      module HtmlTransformers
        ##
        # Transformer that converts relative URLs to absolute URLs within specified HTML elements.
        class TransformUrlsToAbsoluteOnes
          URL_ELEMENTS_WITH_URL_ATTRIBUTE = {
            'a' => :href, # Visible link
            'img' => :src, # Visible image
            'iframe' => :src, # Embedded frame (visible content)
            'audio' => :src, # Can show controls, so potentially visible
            'video' => :src # Video player is visible
          }.freeze

          def initialize(channel_url)
            @channel_url = channel_url
          end

          ##
          # Transforms URLs to absolute ones.
          #
          # @param node_name [String] node name currently being transformed
          # @param node [Nokogiri::XML::Node] node currently being transformed
          # @param _env [Hash] transformer context
          # @option _env [Object] :_reserved reserved for transformer pipeline context
          def call(node_name:, node:, **_env)
            return unless URL_ELEMENTS_WITH_URL_ATTRIBUTE.key?(node_name)

            url_attribute = URL_ELEMENTS_WITH_URL_ATTRIBUTE[node_name]
            url = node[url_attribute]
            node[url_attribute] = Url.from_relative(url, @channel_url).to_s
          end
        end
      end
    end
  end
end
