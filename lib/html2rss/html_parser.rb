# frozen_string_literal: true

require 'concurrent/atomic/atomic_reference'
require 'nokogiri'

module Html2rss
  ##
  # Provides an abstraction layer around the HTML parsing backend.
  #
  # All Html2rss code should interact with HTML parsing via this class so the
  # underlying backend can be swapped (e.g. Nokogiri, Nokolexbor, REXML).
  # The backend must respond to the public methods defined here.
  class HtmlParser
    BACKEND = Concurrent::AtomicReference.new

    class << self
      ##
      # Sets the parser backend.
      #
      # @param backend [Object] object responding to parser interface
      def use(backend)
        backend_ref.value = backend
      end

      ##
      # @return [Object] the configured parser backend
      def backend
        backend_ref.value || initialize_backend
      end

      ##
      # Parses an HTML document string.
      #
      # @param html [String]
      # @return [Object] backend specific document
      def parse_html(html)
        backend.parse_html(html)
      end

      ##
      # Parses an HTML fragment string.
      #
      # @param html [String]
      # @return [Object]
      def parse_html_fragment(html)
        backend.parse_html_fragment(html)
      end

      ##
      # Parses an HTML5 fragment string.
      #
      # @param html [String]
      # @return [Object]
      def parse_html5_fragment(html)
        backend.parse_html5_fragment(html)
      end

      ##
      # @return [Class] backend specific HTML document class
      def document_class
        backend.document_class
      end

      ##
      # @return [Class] backend specific HTML fragment class
      def fragment_class
        backend.fragment_class
      end

      ##
      # @return [Class] backend specific XML element class
      def element_class
        backend.element_class
      end

      ##
      # @return [Class] backend specific XML node class
      def node_class
        backend.node_class
      end

      ##
      # @return [Class] backend specific XML node set class
      def node_set_class
        backend.node_set_class
      end

      ##
      # Creates a new node using the backend.
      #
      # @param name [String] node name
      # @param document [Object] backend specific document
      # @return [Object]
      def create_node(name, document)
        backend.create_node(name, document)
      end

      private

      def backend_ref
        BACKEND
      end

      def initialize_backend
        backend_ref.compare_and_set(nil, Backends::Nokogiri.new)
        backend_ref.value
      end
    end

    module Backends
      ##
      # Default backend powered by Nokogiri.
      class Nokogiri
        ##
        # Parses an HTML document string.
        #
        # @param html [String]
        # @return [Nokogiri::HTML::Document]
        def parse_html(html)
          ::Nokogiri::HTML(html)
        end

        ##
        # Parses an HTML fragment string.
        #
        # @param html [String]
        # @return [Nokogiri::HTML::DocumentFragment]
        def parse_html_fragment(html)
          ::Nokogiri::HTML.fragment(html)
        end

        ##
        # Parses an HTML5 fragment string.
        #
        # @param html [String]
        # @return [Nokogiri::HTML5::DocumentFragment]
        def parse_html5_fragment(html)
          ::Nokogiri::HTML5.fragment(html)
        end

        ##
        # @return [Class]
        def document_class
          ::Nokogiri::HTML::Document
        end

        ##
        # @return [Class]
        def fragment_class
          ::Nokogiri::HTML::DocumentFragment
        end

        ##
        # @return [Class]
        def element_class
          ::Nokogiri::XML::Element
        end

        ##
        # @return [Class]
        def node_class
          ::Nokogiri::XML::Node
        end

        ##
        # @return [Class]
        def node_set_class
          ::Nokogiri::XML::NodeSet
        end

        ##
        # @param name [String]
        # @param document [Nokogiri::XML::Document]
        # @return [Nokogiri::XML::Node]
        def create_node(name, document)
          ::Nokogiri::XML::Node.new(name, document)
        end
      end
    end
  end
end
