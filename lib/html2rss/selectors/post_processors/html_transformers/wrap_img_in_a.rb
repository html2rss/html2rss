# frozen_string_literal: true

module Html2rss
  class Selectors
    module PostProcessors
      module HtmlTransformers
        ##
        # Transformer that wraps <img> tags into <a> tags linking to `img.src`.
        class WrapImgInA
          ##
          # Wraps <img> tags into <a> tags that link to `img.src`.
          #
          # @param node_name [String]
          # @param node [Nokogiri::XML::Node]
          # @return [nil]
          def call(node_name:, node:, **_env)
            return unless already_wrapped?(node_name, node)

            wrap_image_in_anchor(node)
          end

          def already_wrapped?(node_name, node)
            node_name == 'img' && node.parent.name != 'a'
          end

          private

          ##
          # Wraps the <img> node in an <a> tag.
          #
          # @param node [Nokogiri::XML::Node]
          # @return [nil]
          def wrap_image_in_anchor(node)
            anchor = Nokogiri::XML::Node.new('a', node.document)
            anchor['href'] = node['src']
            node.add_next_sibling(anchor)
            anchor.add_child(node.remove)
          end
        end
      end
    end
  end
end
