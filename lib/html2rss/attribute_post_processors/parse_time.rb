module Html2rss
  module AttributePostProcessors
    class ParseTime
      def initialize(value, _options, _item)
        @value = value
      end

      ##
      # @return [String] rfc822 formatted time
      def get
        Time.parse(@value).rfc822
      end
    end
  end
end
