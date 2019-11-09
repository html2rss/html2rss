module Html2rss
  ##
  # Provides a namespace for item extractors.
  module ItemExtractors
    DEFAULT = 'text'.freeze

    def self.get_extractor(name)
      @get_extractor ||= Hash.new do |extractors, key|
        extractors[key] = Utils.get_class_from_name(key || DEFAULT, 'ItemExtractors')
      end

      @get_extractor[name]
    end

    ##
    # @return [Nokogiri::XML::Element]
    def self.element(xml, options)
      selector = options[:selector]
      selector ? xml.css(selector) : xml
    end
  end
end
