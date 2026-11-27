# frozen_string_literal: true

require 'date'
require 'tzinfo'

module Html2rss
  class AutoSource
    module ArticleRules
      ##
      # DOM-agnostic datetime aggregation for article published_at.
      module Date
        # Skip DateTime.parse above this length (Ruby parse is not a validator).
        MAX_DATE_CHARS = Description::MAX_DATE_CHARS
        # Prefer standard time when a local clock time occurs twice (DST fall-back).
        AMBIGUOUS_DST = false
        # Most consecutive fragment lines read together as one date.
        MAX_RUN_LINES = 6

        class << self
          ##
          # @param datetime_strings [Array<String, nil>] raw datetime attribute values
          # @param leftover_lines [Array<String>] leftover visible lines (already split)
          # @param time_zone [String] channel time zone for naive values
          # @return [DateTime, nil] earliest successfully parsed instant
          def earliest(datetime_strings, leftover_lines: [], time_zone: 'UTC')
            values = Array(datetime_strings).filter_map { |value| parse_attr(value, time_zone:) }
            date_runs(leftover_lines).each do |run|
              parsed = parse_line(run.join(' '), time_zone:)
              values << parsed if parsed
            end
            values.min
          end

          ##
          # @param lines [Array<String>] leftover visible lines
          # @return [Array<String>] +lines+ without the ones that read as a date, alone or scattered over
          #   consecutive fragment lines ("November", "25", ",", "2026")
          def without_dates(lines)
            used = date_runs(lines).flatten(1).map(&:object_id)
            Array(lines).reject { |line| used.include?(line.object_id) }
          end

          ##
          # @param time_zone [String] channel time zone
          # @return [::Date] today's calendar day in +time_zone+
          def local_today(time_zone:) = timezone_for(time_zone).now.to_date

          ##
          # @param date [::Date] calendar day
          # @param time_zone [String] channel time zone
          # @return [DateTime] midnight of +date+ in +time_zone+
          def at_midnight(date, time_zone:) = localize(DateTime.new(date.year, date.month, date.day), time_zone)

          ##
          # @param string [String] raw datetime text
          # @param time_zone [String, nil] channel time zone for a naive value (nil reads as UTC)
          # @return [DateTime, nil] parsed instant; naive values are read in +time_zone+
          def parse_datetime(string, time_zone:)
            parsed = DateTime.parse(string, limit: MAX_DATE_CHARS)
            naive?(string) ? localize(parsed, time_zone) : parsed
          rescue ArgumentError, TypeError
            nil
          end

          private

          # Consecutive line runs (shortest first, at most MAX_RUN_LINES) that read as one date.
          def date_runs(lines)
            lines = Array(lines)
            runs = []
            index = 0
            while index < lines.length
              run = (1..MAX_RUN_LINES).lazy.map { |size| lines[index, size] }
                                      .find { |candidate| Description.date_shaped?(candidate.join(' ')) }
              runs << run if run
              index += run ? run.length : 1
            end
            runs
          end

          def parse_attr(value, time_zone:)
            parse_datetime(value.to_s.strip, time_zone:)
          end

          def parse_line(line, time_zone:)
            return unless Description.date_shaped?(line)

            parse_datetime(Description.date_core(line), time_zone:)
          end

          # Naive unless the parser resolved a real offset: unknown words ("Uhr", "ET") leave it nil, and a
          # single-letter military zone other than Z ("h") is a stray letter, not a zone.
          def naive?(string)
            parsed = DateTime._parse(string, limit: MAX_DATE_CHARS)
            zone = parsed[:zone]
            parsed[:offset].nil? || (zone.length == 1 && !zone.casecmp?('z'))
          end

          def localize(datetime, time_zone)
            identifier = time_zone.to_s
            identifier = 'UTC' if identifier.empty?
            at_local(timezone_for(identifier), datetime)
          rescue TZInfo::PeriodNotFound
            at_local(timezone_for('UTC'), datetime)
          end

          def at_local(timezone, datetime)
            timezone.local_datetime(datetime.year, datetime.month, datetime.day,
                                    datetime.hour, datetime.min, datetime.sec, 0, AMBIGUOUS_DST, &:first)
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
