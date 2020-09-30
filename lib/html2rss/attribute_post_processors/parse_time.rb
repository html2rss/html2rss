# frozen_string_literal: true

require 'active_support'
require 'active_support/core_ext/time'

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
    #          time_zone: 'Europe/Berlin'
    #
    # Would return:
    #    "Tue, 02 Jul 2019 00:00:00 +0200"
    #
    # It uses {https://ruby-doc.org/stdlib-2.5.3/libdoc/time/rdoc/Time.html#method-c-parse Time.parse}.
    class ParseTime
      def initialize(value, env)
        @value = value.to_s
        @time_zone = env[:config].time_zone
      end

      ##
      # @return [String] rfc822 formatted time
      def get
        Time.use_zone(@time_zone) { Time.zone.parse(@value).rfc822 }
      end
    end
  end
end
