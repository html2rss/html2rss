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
        # @param xml [Nokogiri::XML::Document]
        # @param selector [String, nil]
        # @return [Nokogiri::XML::ElementSet] selected XML elements
        def element(xml, selector)
          selector ? xml.css(selector) : xml
        end

        ##
        # Registry dispatcher: resolves the extractor strategy for +config+,
        # instantiates it with typed +Args+, and executes its +#call+.
        #
        # @param config [Hash{Symbol => Object}]
        #   Should contain at least `:extractor` (the name) and options for that extractor.
        # @param xml [Nokogiri::XML::Node, Nokogiri::XML::NodeSet]
        # @return [Object] extracted value from the strategy instance
        def call(config, xml)
          extractor_class = NAME_TO_CLASS[config[:extractor]&.to_sym || DEFAULT_EXTRACTOR]
          args = extractor_class::Args.new(
            **config.slice(*extractor_class::Args.members)
          )

          extractor_class.new(xml, args).call
        end
      end
    end
  end
end
