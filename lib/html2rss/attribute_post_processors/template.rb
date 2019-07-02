require 'sanitize'

module Html2rss
  module AttributePostProcessors
    ## Returns a formatted String according to the string pattern.
    #
    # If +self+ is given as a method, the extracted value will be used.
    #
    # Imagine this HTML:
    #    <li>
    #      <h1>Product</h1>
    #      <span class="price">23,42€</span>
    #    </li>
    #
    # YAML usage example:
    #
    #    selectors:
    #      items:
    #        selector: 'li'
    #      price:
    #       selector: '.price'
    #      title:
    #        selector: h1
    #        post_process:
    #         name: template
    #         string: '%s (%s)'
    #         methods:
    #           - self
    #           - price
    #
    # Would return:
    #    'Product (23,42€)'
    class Template
      def initialize(value, options, item)
        @value = value
        @options = options
        @item = item
      end

      ##
      # - uses {http://ruby-doc.org/core-2.6.3/String.html#method-i-25 String#%}
      # @return [String]
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
            @item.public_send(method.to_sym)
          end
        }
      end
    end
  end
end
