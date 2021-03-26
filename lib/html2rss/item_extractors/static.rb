# frozen_string_literal: true

module Html2rss
  module ItemExtractors
    ##
    # YAML usage example:
    #
    #    selectors:
    #      autor:
    #        extractor: static
    #        static: Foobar
    #
    # Would return:
    #    'Foobar'
    class Static
      REQUIRED_OPTIONS = [:static].freeze

      ##
      # @param _xml [nil, Nokogiri::XML::Element]
      # @param options [Struct::StaticOptions]
      def initialize(_xml, options)
        @options = options
      end

      # Returns what options[:static] holds.
      #
      #    options = { static: 'Foobar' }
      #    Static.new(xml, options).get
      #    # => 'Foobar'
      # @return [String, Symbol]
      def get
        @options.static
      end
    end
  end
end
