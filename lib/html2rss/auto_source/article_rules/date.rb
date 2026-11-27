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

        # Fields that name the date by themselves, so Ruby needs no reference day to complete them.
        SELF_DATED = %i[year cwyear].freeze

        class << self
          ##
          # @param datetime_strings [Array<String, nil>] raw datetime attribute values
          # @param leftover_lines [Array<String>] leftover visible lines (already split)
          # @param time_zone [String] channel time zone for naive values
          # @param now [Time] the current time, which gives a date without a year its year
          # @return [DateTime, nil] earliest successfully parsed instant
          def earliest(datetime_strings, now:, leftover_lines: [], time_zone: 'UTC')
            values = Array(datetime_strings).filter_map { |value| parse_attr(value, time_zone:, now:) }
            date_runs(leftover_lines).each do |run|
              parsed = parse_line(run.join(' '), time_zone:, now:)
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
          # @param now [Time] the current time
          # @return [::Date] today's calendar day in +time_zone+
          def local_today(time_zone:, now:) = timezone_for(time_zone).to_local(now).to_date

          ##
          # @param date [::Date] calendar day
          # @param time_zone [String] channel time zone
          # @return [DateTime] midnight of +date+ in +time_zone+
          def at_midnight(date, time_zone:) = localize(DateTime.new(date.year, date.month, date.day), time_zone)

          ##
          # @param string [String] raw datetime text
          # @param time_zone [String, nil] channel time zone for a naive value (nil reads as UTC)
          # @param now [Time] the current time, which completes a date the text leaves partial
          # @return [DateTime, nil] parsed instant; naive values are read in +time_zone+
          def parse_datetime(string, time_zone:, now:)
            fields = DateTime._parse(string, limit: MAX_DATE_CHARS)
            return unless (parsed = parse(fields, string, local_today(time_zone:, now:)))

            naive?(fields) ? localize(parsed, time_zone) : parsed
          rescue ArgumentError, TypeError
            nil
          end

          private

          # Consecutive line runs (longest first, at most MAX_RUN_LINES) that read as one date.
          def date_runs(lines)
            lines = Array(lines)
            runs = []
            index = 0
            while index < lines.length
              run = MAX_RUN_LINES.downto(1).lazy.map { |size| lines[index, size] }
                                 .find { |candidate| Description.date_shaped?(candidate.join(' ')) }
              runs << run if run
              index += run ? run.length : 1
            end
            runs
          end

          # Ruby completes a partial date from the system date; the same completion is read here from +today+.
          # Weekday and week-number shapes name no day on their own and read as nil. The caller's +_parse+ holds the
          # length limit.
          def parse(fields, string, today)
            return DateTime.parse(string) if fields.keys.intersect?(SELF_DATED)
            return unless (day = reference_day(fields, today))

            hour, min, sec = fields.values_at(:hour, :min, :sec).map(&:to_i)
            DateTime.new(day.year, day.month, day.day, hour, min, sec + fields.fetch(:sec_fraction, 0),
                         Rational(fields[:offset].to_i, 86_400))
          end

          # A day of the year, a month and day, or a day alone takes what it lacks from the year and month of
          # +today+; a time alone is +today+; a month alone is its first day.
          def reference_day(fields, today)
            if fields.key?(:yday)
              ::Date.ordinal(today.year, fields.fetch(:yday))
            elsif fields.key?(:mon) || fields.key?(:mday)
              ::Date.new(today.year, fields.fetch(:mon, today.month), fields.fetch(:mday, 1))
            elsif fields.key?(:hour)
              today
            end
          end

          def parse_attr(value, time_zone:, now:)
            parse_datetime(value.to_s.strip, time_zone:, now:)
          end

          def parse_line(line, time_zone:, now:)
            return unless Description.date_shaped?(line)

            parse_datetime(Description.date_core(line), time_zone:, now:)
          end

          # Naive unless the parser resolved a real offset: unknown words ("Uhr", "ET") leave it nil, and a
          # single-letter military zone other than Z ("h") is a stray letter, not a zone.
          def naive?(fields)
            zone = fields[:zone]
            fields[:offset].nil? || (zone.length == 1 && !zone.casecmp?('z'))
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
