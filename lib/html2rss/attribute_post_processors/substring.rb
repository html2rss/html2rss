module Html2rss
  module AttributePostProcessors
    ## Returns a defined part of a String.
    #
    # The +end+ parameter can be omitted, in that case it will not cut the
    # String at the end.
    #
    # Imagine this HTML:
    #    <h1>Foo bar and baz<h1>
    #
    # YAML usage example:
    #    selectors:
    #      title:
    #        selector: h1
    #        post_process:
    #         name: substring
    #         start: 4
    #         end: 6
    #
    # Would return:
    #    'bar'
    class Substring
      def initialize(value, options, _item)
        @value = value
        @options = options
      end

      ##
      # @return [String]
      def get
        ending = @options.fetch('end', @value.length).to_i
        @value[@options['start'].to_i..ending]
      end
    end
  end
end
