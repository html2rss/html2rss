require 'sanitize'

module Html2rss
  module AttributePostProcessors
    class Template
      def initialize(value, options, item)
        @value = value
        @options = options
        @item = item
      end

      def get
        string % methods
      end

      private

      def string
        @options['string']
      end

      def methods
        @methods ||= @options['methods'].map { |method|
          if method == 'self'
            @value
          else
            @item.send(method.to_sym)&.to_s
          end
        }
      end
    end
  end
end
