module Html2rss
  ##
  # Provides a namespace for item extractors.
  module ItemExtractors
    DEFAULT = 'Text'.freeze

    def self.get_extractor(name)
      @get_extractor ||= Hash.new do |extractors, key|
        camel_cased_name = (key || DEFAULT).split('_').map(&:capitalize).join
        class_name = ['Html2rss', 'ItemExtractors', camel_cased_name].join('::')
        extractors[key] = Object.const_get(class_name)
      end

      @get_extractor[name]
    end

    ##
    # @return [Nokogiri::XML::Element]
    def self.element(xml, options)
      selector = options['selector']
      selector ? xml.css(selector) : xml
    end
  end
end
