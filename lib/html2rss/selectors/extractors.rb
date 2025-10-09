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

      ##
      # Maps the extractor class to its corresponding options class.
      ITEM_OPTION_CLASSES = Hash.new do |hash, klass|
        hash[klass] = klass.const_get(:Options)
      end

      DEFAULT_EXTRACTOR = :text

      class << self
        ##
        # Retrieves elements from the configured HTML backend based on the selector.
        #
        # @param xml [Object]
        # @param selector [String, nil]
        # @return [Object] selected elements
        def element(xml, selector)
          selector ? xml.css(selector) : xml
        end

        # @param attribute_options [Hash<Symbol, Object>]
        #   Should contain at least `:extractor` (the name) and required options for that extractor.
        # @param xml [Object]
        # @return [Object] instance of the specified item extractor class
        def get(attribute_options, xml)
          extractor_class = NAME_TO_CLASS[attribute_options[:extractor]&.to_sym || DEFAULT_EXTRACTOR]
          options = ITEM_OPTION_CLASSES[extractor_class].new(attribute_options.slice(*extractor_class::Options.members))

          extractor_class.new(xml, options).get
        end
      end
    end
  end
end
