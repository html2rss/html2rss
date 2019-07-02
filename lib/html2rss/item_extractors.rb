require_relative 'item_extractors/attribute'
require_relative 'item_extractors/current_time'
require_relative 'item_extractors/href'
require_relative 'item_extractors/html'
require_relative 'item_extractors/static'
require_relative 'item_extractors/text'

module Html2rss
  ##
  # Provides a namespace for item extractors.
  module ItemExtractors
    DEFAULT = 'text'.freeze

    def self.get_extractor(name)
      name ||= DEFAULT
      camel_cased_name = name.split('_').map(&:capitalize).join
      class_name = ['Html2rss', 'ItemExtractors', camel_cased_name].join('::')

      Object.const_get(class_name)
    end

    ##
    # @return [Nokogiri::XML::Element]
    def self.element(xml, options)
      selector = options['selector']
      selector ? xml.css(selector) : xml
    end
  end
end
