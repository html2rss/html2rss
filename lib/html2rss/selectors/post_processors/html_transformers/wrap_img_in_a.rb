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
          # @param node [Object]
          # @return [nil]
          def call(node_name:, node:, **_env)
            return unless should_process?(node_name)

            wrap_image_in_anchor(node) unless already_wrapped?(node)
          end

          def should_process?(node_name)
            node_name == 'img'
          end

          def already_wrapped?(node)
            node.parent.name == 'a'
          end

          private

          ##
          # Wraps the <img> node in an <a> tag.
          #
          # @param node [Object]
          # @return [nil]
          def wrap_image_in_anchor(node)
            anchor = HtmlParser.create_node('a', node.document)
            anchor['href'] = node['src']
            node.add_next_sibling(anchor)
            anchor.add_child(node.remove)
          end
        end
      end
    end
  end
end
