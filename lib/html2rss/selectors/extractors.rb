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

        # @param attribute_options [Hash{Symbol => Object}]
        #   Should contain at least `:extractor` (the name) and required options for that extractor.
        # @param xml [Nokogiri::XML::Document]
        # @return [Object] instance of the specified item extractor class
        def call(attribute_options, xml)
          extractor_class = NAME_TO_CLASS[attribute_options[:extractor]&.to_sym || DEFAULT_EXTRACTOR]
          args = extractor_class::Args.new(
            **attribute_options.slice(*extractor_class::Args.members)
          )

          extractor_class.new(xml, args).call
        end
      end
    end
  end
end
