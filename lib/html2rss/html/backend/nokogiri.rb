# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  module Html
    module Backend
      ##
      # Nokogiri (libxml) HTML adapter — production default.
      module Nokogiri
        module_function

        # @return [Symbol]
        def name = :nokogiri

        ##
        # @param html [String]
        # @return [Nokogiri::HTML::Document]
        def parse(html)
          ::Nokogiri::HTML(html)
        end

        ##
        # @param html [String]
        # @return [Nokogiri::HTML::DocumentFragment]
        def fragment(html)
          ::Nokogiri::HTML5.fragment(html)
        end

        ##
        # @param obj [Object]
        # @return [Boolean]
        def html_document?(obj)
          obj.is_a?(::Nokogiri::HTML::Document)
        end

        ##
        # @param obj [Object]
        # @return [Boolean]
        def node?(obj)
          obj.is_a?(::Nokogiri::XML::Node)
        end

        ##
        # @param obj [Object]
        # @return [Boolean]
        def node_set?(obj)
          obj.is_a?(::Nokogiri::XML::NodeSet)
        end

        ##
        # Drop HTML comments in-place without XPath (Lexbor-portable).
        #
        # @param doc [Nokogiri::XML::Node]
        # @return [void]
        def remove_comments!(doc)
          doc.traverse do |node|
            node.remove if node.comment?
          end
        end

        ##
        # @return [Class] parse / syntax errors from this backend
        def syntax_error_class = ::Nokogiri::SyntaxError
      end
    end
  end
end
