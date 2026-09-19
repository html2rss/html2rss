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
        # Attribute-style extractors pass +first: true+ so Nokogiri can use +at_css+
        # when only the first match is consumed. Text/HTML keep +css+ so every
        # match is concatenated. Category collection also uses the default.
        #
        # @param xml [Nokogiri::XML::Document, Nokogiri::XML::Node]
        # @param selector [String, nil]
        # @param first [Boolean] when true, return the first match via +at_css+
        # @return [Nokogiri::XML::Node, Nokogiri::XML::NodeSet, nil] selected XML elements
        def element(xml, selector, first: false)
          return xml unless selector

          first ? xml.at_css(selector) : xml.css(selector)
        end

        ##
        # Registry dispatcher: resolves the extractor strategy for +config+,
        # instantiates it with options, and executes its +#call+.
        #
        # +base_url+ and +selector+ can be supplied without merging a new Hash
        # into the (static) field config on every item.
        #
        # @param config [Hash{Symbol => Object}]
        #   Should contain at least `:extractor` (the name) and options for that extractor.
        # @param xml [Nokogiri::XML::Node, Nokogiri::XML::NodeSet]
        # @param base_url [String, Html2rss::Url, nil] page base URL for relative hrefs
        # @param selector [String, nil] CSS selector override (pass +nil+ to use +xml+ as-is)
        # @return [Object] extracted value from the strategy instance
        def call(config, xml, base_url: nil, selector: config[:selector])
          extractor_class = NAME_TO_CLASS[config[:extractor]&.to_sym || DEFAULT_EXTRACTOR]
          extractor_class.new(
            xml,
            selector:,
            attribute: config[:attribute],
            static: config[:static],
            base_url: base_url || config[:base_url]
          ).call
        end
      end
    end
  end
end
