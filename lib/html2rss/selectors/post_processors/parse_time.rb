# frozen_string_literal: true

require 'time'
require 'tzinfo'

module Html2rss
  class Selectors
    module PostProcessors
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
        # Expected Ruby class for the extracted value before this post-processor runs.
        VALUE_TYPE = String

        # JSON Schema description exported via +schema_doc+.
        DESCRIPTION = 'Parse a time string with Time.parse and return RFC822, using the channel `time_zone`.'

        # Example post-process objects for JSON Schema +examples+.
        EXAMPLES = [
          { 'name' => 'parse_time' }
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this post-processor
        def self.schema_doc = SchemaDoc.for_post_processor(name: :parse_time, klass: self)

        ##
        # Ensures +context.time_zone+ is a non-empty String before parsing.
        #
        # @param _value [String] extracted time string (unused; type-checked via VALUE_TYPE)
        # @param context [Selectors::Context] must carry a usable +time_zone+
        # @return [void]
        # @raise [ArgumentError] when time_zone is nil or empty
        def self.validate_args!(_value, context)
          time_zone_value = context.time_zone

          if time_zone_value.nil? || time_zone_value.empty?
            raise ArgumentError, 'time_zone cannot be nil or empty', [], cause: nil
          end

          assert_type(time_zone_value, String, :time_zone, context:)
        end

        ##
        # Converts the provided time string to RFC822 format, taking into account the time_zone.
        #
        # @return [String] RFC822 formatted time
        # @raise [TZInfo::InvalidTimezoneIdentifier] if the configured time zone is invalid
        def get
          with_timezone(context.time_zone) { Time.parse(value).rfc822 }
        end

        private

        def with_timezone(time_zone)
          return yield if time_zone.nil? || time_zone.empty?

          # Validate timezone using TZInfo
          TZInfo::Timezone.get(time_zone)

          prev_tz = ENV.fetch('TZ', Time.now.getlocal.zone)
          ENV['TZ'] = time_zone
          yield
        ensure
          ENV['TZ'] = prev_tz if prev_tz
        end
      end
    end
  end
end
