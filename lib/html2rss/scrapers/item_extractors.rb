# frozen_string_literal: true

module Html2rss
  module Scrapers
    ##
    # Provides a namespace for item extractors.
    module ItemExtractors
      ##
      # The Error class to be thrown when an unknown extractor name is requested.
      class UnknownExtractorName < Html2rss::Error; end

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

      ##
      # Retrieves an element from Nokogiri XML based on the selector.
      #
      # @param xml [Nokogiri::XML::Document]
      # @param selector [String, nil]
      # @return [Nokogiri::XML::ElementSet] selected XML elements
      def self.element(xml, selector)
        selector ? xml.css(selector) : xml
      end

      ##
      # Creates an instance of the requested item extractor.
      #
      # @param attribute_options [Hash<Symbol, Object>]
      #   Should contain at least `:extractor` (the name) and required options for that extractor.
      # @param xml [Nokogiri::XML::Document]
      # @return [Object] instance of the specified item extractor class
      def self.item_extractor_factory(attribute_options, xml)
        extractor_name = attribute_options[:extractor]&.to_sym || DEFAULT_EXTRACTOR
        extractor_class = find_extractor_class(extractor_name)
        options_instance = build_options_instance(extractor_class, attribute_options)
        create_extractor_instance(extractor_class, xml, options_instance)
      end

      ##
      # Finds the extractor class based on the name.
      #
      # @param extractor_name [Symbol] the name of the extractor
      # @return [Class] the class implementing the extractor
      # @raise [UnknownExtractorName] if the extractor class is not found
      def self.find_extractor_class(extractor_name)
        NAME_TO_CLASS[extractor_name] || raise(UnknownExtractorName,
                                               "Unknown extractor name '#{extractor_name}' requested in NAME_TO_CLASS")
      end

      ##
      # Builds the options instance for the extractor class.
      #
      # @param extractor_class [Class] the class implementing the extractor
      # @param attribute_options [Hash<Symbol, Object>] the attribute options
      # @return [Object] an instance of the options class for the extractor
      def self.build_options_instance(extractor_class, attribute_options)
        options = attribute_options.slice(*extractor_class::Options.members)
        ITEM_OPTION_CLASSES[extractor_class].new(options)
      end

      ##
      # Creates an instance of the extractor class.
      #
      # @param extractor_class [Class] the class implementing the extractor
      # @param xml [Nokogiri::XML::Document] the XML document
      # @param options_instance [Object] the options instance
      # @return [Object] an instance of the extractor class
      def self.create_extractor_instance(extractor_class, xml, options_instance)
        extractor_class.new(xml, options_instance)
      end
    end
  end
end
