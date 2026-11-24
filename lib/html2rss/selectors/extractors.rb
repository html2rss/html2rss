# frozen_string_literal: true

module Html2rss
  class Selectors
    ##
    # Provides a namespace for item extractors.
    module Extractors
      ##
      # Maps the extractor name to the class implementing the extractor.
      #
      # The key is the name to use in the feed config.
      NAME_TO_CLASS = {
        attribute: Attribute,
        href: Href,
        html: Html,
        static: Static,
        text: Text
      }.freeze

      # Extractor used when none is explicitly configured.
      DEFAULT_EXTRACTOR = :text
      class << self
        ##
        # Retrieves an element from Nokogiri XML based on the selector.
        #
        # Attribute-style extractors use {.first_element} so Nokogiri can use +at_css+
        # when only the first match is consumed. Text/HTML keep +css+ so every
        # match is concatenated. Category collection also uses the default.
        #
        # @param xml [Nokogiri::XML::Document, Nokogiri::XML::Node]
        # @param selector [String, nil]
        # @return [Nokogiri::XML::Node, Nokogiri::XML::NodeSet, nil] selected XML elements
        def element(xml, selector)
          return xml unless selector

          xml.css(selector)
        end

        ##
        # Like {.element} for attribute-style extractors that consume only the first match.
        #
        # @param xml [Nokogiri::XML::Document, Nokogiri::XML::Node]
        # @param selector [String, nil]
        # @return [Nokogiri::XML::Node, nil] the first selected element
        def first_element(xml, selector)
          return xml unless selector

          xml.at_css(selector)
        end
      end
    end
  end
end
