# frozen_string_literal: true

require 'date'
require 'tzinfo'

module Html2rss
  module Html
    module ArticleRules
      ##
      # DOM-agnostic datetime aggregation for article published_at.
      module Date
        # Skip DateTime.parse above this length (Ruby parse is not a validator).
        MAX_DATE_CHARS = Description::MAX_DATE_CHARS
        # Trailing offset / Zulu marker — present means the string already has a zone.
        OFFSET = /(?:Z|[+-]\d{2}:?\d{2})\z/i

        class << self
          ##
          # @param datetime_strings [Array<String, nil>] raw datetime attribute values
          # @param leftover_lines [Array<String>] leftover visible lines (already split)
          # @param time_zone [String] channel time zone for naive values
          # @return [DateTime, nil] earliest successfully parsed instant
          def earliest(datetime_strings, leftover_lines: [], time_zone: 'UTC')
            values = Array(datetime_strings).filter_map { |value| parse_attr(value, time_zone:) }
            Array(leftover_lines).each do |line|
              parsed = parse_line(line, time_zone:)
              values << parsed if parsed
            end
            values.min
          end

          private

          def parse_attr(value, time_zone:)
            parse_datetime(value.to_s.strip, time_zone:)
          end

          def parse_line(line, time_zone:)
            return unless Description.date_shaped?(line)

            parse_datetime(Description.date_core(line), time_zone:)
          end

          def parse_datetime(string, time_zone:)
            return if string.empty? || string.length > MAX_DATE_CHARS

            parsed = DateTime.parse(string, limit: MAX_DATE_CHARS)
            naive?(string) ? localize(parsed, time_zone) : parsed
          rescue ArgumentError, TypeError
            nil
          end

          def naive?(string) = !string.match?(OFFSET)

          def localize(datetime, time_zone)
            identifier = time_zone.to_s
            identifier = 'UTC' if identifier.empty?
            tz = timezone_for(identifier)
            tz.local_datetime(datetime.year, datetime.month, datetime.day,
                              datetime.hour, datetime.min, datetime.sec)
          rescue TZInfo::PeriodNotFound, TZInfo::AmbiguousTime
            datetime
          end

          def timezone_for(identifier)
            TZInfo::Timezone.get(identifier)
          rescue TZInfo::InvalidTimezoneIdentifier
            TZInfo::Timezone.get('UTC')
          end
        end
      end
    end
  end
end
