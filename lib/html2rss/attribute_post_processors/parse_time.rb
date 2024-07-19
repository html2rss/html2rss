# frozen_string_literal: true

require 'time'
require_relative '../utils'

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
      ##
      # @param value [String] the time to parse
      # @param env [Item::Context] Context object providing additional environment details
      def initialize(value, env)
        @value = value.to_s
        @time_zone = env[:config].time_zone
      end

      ##
      # Converts the provided time string to RFC822 format, taking into account the configured time zone.
      #
      # @return [String] RFC822 formatted time
      def get
        Utils.use_zone(@time_zone) { Time.parse(@value).rfc822 }
      end
    end
  end
end
