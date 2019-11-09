require 'sanitize'

module Html2rss
  module AttributePostProcessors
    ## Returns a formatted String according to the string pattern.
    #
    # If +self+ is used, the selectors extracted value will be used.
    # It uses [Kernel#format](https://ruby-doc.org/core/Kernel.html#method-i-format)
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
    #          name: template
    #          string: '%{self} (%{price})'
    #
    # Would return:
    #    'Product (23,42€)'
    class Template
      def initialize(value, env)
        @value = value
        @options = env[:options]
        @item = env[:item]
        @string = @options[:string]
      end

      ##
      # @return [String]
      def get
        return format_string_with_methods if @options[:methods]

        names = string.scan(/%[<|{](\w*)[>|}]/)
        names.flatten!
        names.compact!
        names.map!(&:to_sym)

        format(string, names.map { |name| [name, item_value(name)] }.to_h)
      end

      private

      attr_reader :string

      def methods
        @methods ||= @options[:methods].map(&method(:item_value))
      end

      def format_string_with_methods
        string % methods
      end

      def item_value(method_name)
        method_name.to_sym == :self ? @value.to_s : @item.public_send(method_name).to_s
      end
    end
  end
end
