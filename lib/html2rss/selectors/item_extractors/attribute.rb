# frozen_string_literal: true

module Html2rss
  class Selectors
    module ItemExtractors
      ##
      # Returns the value of the attribute.
      #
      # Imagine this +time+ HTML tag with a +datetime+ attribute:
      #
      #     <time datetime="2019-07-01">...</time>
      #
      # YAML usage example:
      #
      #    selectors:
      #      link:
      #        selector: time
      #        extractor: attribute
      #        attribute: datetime
      #
      # Would return:
      #    '2019-07-01'
      #
      # In case you're extracting a date or a time, consider parsing it
      # during post processing with {AttributePostProcessors::ParseTime}.
      class Attribute
        # The available options for the attribute extractor.
        Options = Struct.new('AttributeOptions', :selector, :attribute, keyword_init: true)

        ##
        # Initializes the Attribute extractor.
        #
        # @param xml [Nokogiri::XML::Element]
        # @param options [Options]
        def initialize(xml, options)
          @options = options
          @element = ItemExtractors.element(xml, options.selector)
        end

        ##
        # Retrieves and returns the attribute's value as a string.
        #
        # @return [String] The value of the attribute.
        def get
          @element.attr(@options.attribute).to_s
        end
      end
    end
  end
end
