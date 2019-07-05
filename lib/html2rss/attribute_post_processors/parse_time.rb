module Html2rss
  module AttributePostProcessors
    ##
    # Returns the {https://www.w3.org/Protocols/rfc822/ RFC822} representation of a time.
    #
    # Imagine this HTML structure:
    #
    #     <p>Published on <span>2019-07-02</span></p>
    #
    # YAML usage example:
    #
    #    selectors:
    #      description:
    #        selector: span
    #        post_process:
    #          name: 'parse_time'
    #
    # Would return:
    #    "Tue, 02 Jul 2019 00:00:00 +0200"
    #
    # It uses {https://ruby-doc.org/stdlib-2.5.3/libdoc/time/rdoc/Time.html#method-c-parse Time.parse}.
    # As of now it ignores time zones and always falls back to your system's
    # time zone.
    class ParseTime
      def initialize(value, _options, _item)
        @value = value.to_s
      end

      ##
      # @return [String] rfc822 formatted time
      def get
        Time.parse(@value).utc.rfc822
      end
    end
  end
end
