module Html2rss
  module AttributePostProcessors
    class Substring
      def initialize(value, options, _item)
        @value = value
        @options = options
      end

      def get
        ending = @options.fetch('end', @value.length).to_i
        @value[@options['start'].to_i..ending]
      end
    end
  end
end
