# frozen_string_literal: true

module Html2rss
  ##
  # Provides a namespace for item extractors.
  module ItemExtractors
    DEFAULT = 'text'

    ##
    # @param name [String]
    # @return [Class, nil] the extractor class
    def self.get_extractor(name)
      @get_extractor ||= Hash.new do |extractors, key|
        extractors[key] = Utils.class_from_name(key || DEFAULT, 'ItemExtractors')
      end

      @get_extractor[name]
    end

    ##
    # @param xml [Nokogiri::XML]
    # @param selector [String, nil]
    # @return [Nokogiri::XML::Element]
    def self.element(xml, selector)
      selector ? xml.css(selector) : xml
    end

    ##
    # @param attribute_options [Hash<Symbol, Object>]
    # @param xml [Nokogiri::XML]
    # @return [ItemExtractor::*]
    def self.item_extractor_factory(attribute_options, xml)
      extractor = get_extractor(attribute_options[:extractor])

      @options ||= Hash.new do |hash, klass|
        hash[klass] = Struct.new(
          "#{klass.class.to_s.split('::').last}Option",
          *klass::REQUIRED_OPTIONS,
          keyword_init: true
        )
      end

      extractor.new(xml, @options[extractor].new(attribute_options.slice(*extractor::REQUIRED_OPTIONS)))
    end
  end
end
