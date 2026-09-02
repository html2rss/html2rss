# frozen_string_literal: true

module Html2rss
  module Html
    module Backend
      ##
      # Lexbor HTML adapter via the +nokolexbor+ gem (experiment only).
      #
      # Loaded lazily so the gem can stay a development dependency until promoted.
      # XML / XPath / sitemap paths must not use this backend.
      module Nokolexbor
        module_function

        # @return [Symbol]
        def name = :nokolexbor

        ##
        # @param html [String]
        # @return [Object] Lexbor document (Nokogiri-compatible surface)
        def parse(html)
          gem_root::HTML(html)
        end

        ##
        # @param html [String]
        # @return [Object] document fragment
        def fragment(html)
          gem_root::DocumentFragment.parse(html)
        end

        ##
        # @param obj [Object]
        # @return [Boolean]
        def html_document?(obj)
          obj.is_a?(gem_root::Document)
        end

        ##
        # @param obj [Object]
        # @return [Boolean]
        def node?(obj)
          obj.is_a?(gem_root::Node)
        end

        ##
        # @param obj [Object]
        # @return [Boolean]
        def node_set?(obj)
          obj.is_a?(gem_root::NodeSet)
        end

        ##
        # @param doc [Object]
        # @return [void]
        def remove_comments!(doc)
          doc.traverse do |node|
            node.remove if node.comment?
          end
        end

        ##
        # @return [Class]
        def syntax_error_class = gem_root::Lexbor::Error

        def gem_root
          require 'nokolexbor'
          ::Nokolexbor
        end
        module_function :gem_root
      end
    end
  end
end
