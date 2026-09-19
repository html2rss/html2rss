# frozen_string_literal: true

require 'date'
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

        # JSON Schema description exported via +schema_export+.
        DESCRIPTION = 'Parse a time string with Time.parse and return RFC822, using the channel `time_zone`.'

        # Example post-process objects for JSON Schema +examples+.
        EXAMPLES = [
          { 'name' => 'parse_time' }
        ].freeze

        # @return [Hash{Symbol => Object}] JSON Schema fragment for this post-processor
        def self.schema_export = SchemaExport.for_post_processor(name: :parse_time, klass: self)

        # @param identifier [String] IANA time zone name
        # @return [TZInfo::Timezone]
        def self.timezone(identifier)
          timezones[identifier] ||= TZInfo::Timezone.get(identifier)
        end

        # rubocop:disable-next ThreadSafety/ClassInstanceVariable
        def self.timezones
          @timezones ||= {}
        end
        private_class_method :timezones

        ##
        # Ensures +context.time_zone+ is a non-empty String before parsing.
        #
        # @param _value [String] extracted time string (unused; type-checked via VALUE_TYPE)
        # @param context [Selectors::StepEnv] must carry a usable +time_zone+
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
        # Uses in-memory {TZInfo::Timezone} conversion so parsing never mutates +ENV['TZ']+
        # (which would invalidate libc +tzset+ and re-read zoneinfo from disk).
        #
        # @return [String] RFC822 formatted time
        # @raise [TZInfo::InvalidTimezoneIdentifier] if the configured time zone is invalid
        def call
          parse_time(value, context.time_zone).rfc822
        end

        private

        def parse_time(string, time_zone)
          components = Date._parse(string, false)
          if components[:zone] || components.key?(:offset)
            Time.parse(string)
          else
            local_time_in_zone(components, time_zone)
          end
        end

        def local_time_in_zone(components, time_zone)
          self.class.timezone(time_zone).local_time(
            components[:year],
            components[:mon],
            components[:mday],
            components[:hour] || 0,
            components[:min] || 0,
            (components[:sec] || 0) + (components[:sec_fraction] || 0)
          )
        end
      end
    end
  end
end
