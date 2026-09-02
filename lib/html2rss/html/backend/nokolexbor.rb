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
          gem_root::HTML.fragment(html)
        end

        ##
        # @param obj [Object]
        # @return [Boolean]
        def html_document?(obj)
          obj.is_a?(document_class)
        end

        ##
        # @param obj [Object]
        # @return [Boolean]
        def node?(obj)
          klass = node_class
          klass != ::Object && obj.is_a?(klass)
        end

        ##
        # @param obj [Object]
        # @return [Boolean]
        def node_set?(obj)
          klass = node_set_class
          return obj.is_a?(klass) if klass

          false
        end

        ##
        # @param doc [Object]
        # @return [void]
        def remove_comments!(doc)
          doc.traverse do |node|
            node.remove if node.respond_to?(:comment?) && node.comment?
          end
        end

        ##
        # @return [Class]
        def syntax_error_class
          gem_root.const_defined?(:Error) ? gem_root::Error : StandardError
        end

        def gem_root
          require 'nokolexbor'
          ::Nokolexbor
        end
        module_function :gem_root

        def document_class
          root = gem_root
          return root::Document if root.const_defined?(:Document)

          parse('<html></html>').class
        end
        module_function :document_class

        def node_class
          root = gem_root
          return root::Node if root.const_defined?(:Node)

          ::Object
        end
        module_function :node_class

        def node_set_class
          root = gem_root
          return root::NodeSet if root.const_defined?(:NodeSet)
          return root::NodeCollection if root.const_defined?(:NodeCollection)

          nil
        end
        module_function :node_set_class
      end
    end
  end
end
