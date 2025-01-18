# frozen_string_literal: true

require 'time'

module Html2rss
  module Scrapers
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
      # It uses `Time.parse`.
      class ParseTime < Base
        def self.validate_args!(value, context)
          assert_type(value, String, :value, context:)
          assert_type(time_zone(context), String, :time_zone, context:)
        end

        def self.time_zone(context) = context.dig(:config, :channel, :time_zone)

        ##
        # Converts the provided time string to RFC822 format, taking into account the time_zone.
        #
        # @return [String] RFC822 formatted time
        # @raise [TZInfo::InvalidTimezoneIdentifier] if the configured time zone is invalid
        def get
          Html2rss::Utils.use_zone(time_zone) { Time.parse(value).rfc822 }
        end

        private

        def time_zone
          self.class.time_zone(context)
        end
      end
    end
  end
end
