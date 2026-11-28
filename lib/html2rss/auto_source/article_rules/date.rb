# frozen_string_literal: true

require 'date'
require 'tzinfo'

module Html2rss
  class AutoSource
    module ArticleRules
      ##
      # DOM-agnostic datetime aggregation for article published_at.
      module Date
        # An ASCII digit: every {DATE_SHAPES} entry needs one.
        DIGIT = /\d/
        # Skip date detection / DateTime.parse above this length.
        MAX_DATE_CHARS = 128
        # Optional type-chip / clock separators (ASCII/en/em dash, pipe, bullet).
        CHIP_SEPARATORS = [' - ', ' – ', ' — ', ' | ', ' • '].freeze
        # Whole-line date shapes after normalize (ISO, numeric, day-month, month-day).
        DATE_SHAPES = [
          /\A\d{4}-\d{1,2}-\d{1,2}(?:[T ]\d{1,2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)?\z/i,
          %r{\A\d{1,2}[./-]\d{1,2}[./-]\d{2,4}(?: \d{1,2}:\d{2}(?::\d{2})?)?\z},
          /\A\d{1,2}\.? \p{L}{3,9}\.?(?:\s*,)?\s*\d{4}(?: \d{1,2}:\d{2}(?::\d{2})?)?\z/i,
          /\A\p{L}{3,9}\.? \d{1,2}(?:\s*,)?\s*\d{4}(?: \d{1,2}:\d{2}(?::\d{2})?)?\z/i
        ].freeze
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

          ##
          # @param line [String, nil]
          # @return [Boolean]
          def date_shaped?(line)
            return false unless line.to_s.match?(DIGIT) # every date shape holds a digit

            core = date_core(line)
            return false if core.empty? || core.length > MAX_DATE_CHARS

            DATE_SHAPES.any? { |shape| core.match?(shape) }
          end

          ##
          # @param line [String, nil]
          # @return [String]
          def date_core(line)
            normalized = normalize(line)
            CHIP_SEPARATORS.each do |sep|
              peeled = peel_separator(normalized, sep)
              return peeled if peeled
            end
            normalized
          end

          private

          def peel_separator(normalized, sep)
            idx = normalized.rindex(sep)
            return unless idx

            left = normalized[0, idx]
            right = normalized[(idx + sep.length)..]
            return left if type_chip?(right) || Article::Title.clock_piece?(right)

            right if type_chip?(left)
          end

          # A chip beside a date is peeled whatever the page language: a word that is no marker on a Chinese page
          # (+独自+) is still a type chip once a date stands next to it.
          def type_chip?(text) = Article::Title::TYPE_MARKERS.include?(text.downcase)

          def normalize(line) = line.to_s.gsub(/[[:space:]]+/, ' ').strip

          # Consecutive line runs (longest first, at most MAX_RUN_LINES) that read as one date.
          def date_runs(lines)
            lines = Array(lines)
            runs = []
            index = 0
            while index < lines.length
              run = MAX_RUN_LINES.downto(1).lazy.map { |size| lines[index, size] }
                                 .find { |candidate| date_shaped?(candidate.join(' ')) }
              runs << run if run
              index += run ? run.length : 1
            end
            runs
          end

          def parse_attr(value, time_zone:)
            parse_datetime(value.to_s.strip, time_zone:)
          end

          def parse_line(line, time_zone:)
            return unless date_shaped?(line)

            parse_datetime(date_core(line), time_zone:)
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
