# frozen_string_literal: true

require 'date'

module Html2rss
  class AutoSource
    module Scraper
      class WordpressApi
        class PageScope
          ##
          # Maps scoped archive path segments to WordPress REST +after+/+before+ bounds.
          #
          # Owns date-path shape detection and calendar range math only. Body-class
          # taxonomy/author signals and pagination stay on {Resolver}.
          class DateArchiveRange
            ##
            # @param segments [Array<String>] path segments with pagination already stripped
            # @return [Hash{String => String}, nil] +after+/+before+ ISO8601 bounds, or +nil+
            def self.from_segments(segments)
              components = components_from(segments)
              return unless components

              start_date = Date.new(*components.fetch(:start_date_parts))
              {
                'after' => iso8601_start(start_date),
                'before' => iso8601_start(next_archive_boundary(start_date, components.fetch(:precision)))
              }
            rescue Date::Error
              nil
            end

            ##
            # @param segments [Array<String>] path segments with pagination already stripped
            # @return [Boolean] whether segments match a year[/month[/day]] archive shape
            def self.path?(segments)
              !date_segments_from(segments).nil?
            end

            class << self
              private

              def components_from(segments)
                date_segments = date_segments_from(segments)
                return unless date_segments

                year = date_segments.fetch(0).to_i
                month = parse_archive_segment(date_segments[1], 1, 12)
                day = parse_archive_segment(date_segments[2], 1, 31)

                {
                  start_date_parts: [year, month || 1, day || 1],
                  precision: archive_precision(month:, day:)
                }
              end

              def date_segments_from(segments)
                year_index = segments.find_index { _1.match?(/\A\d{4}\z/) }
                return unless year_index

                date_segments = segments.drop(year_index)
                return unless date_segments.length.between?(1, 3)
                return unless archive_segment_shape?(date_segments)

                date_segments
              end

              def archive_segment_shape?(segments)
                month = segments[1]
                day = segments[2]
                return false if day && month.nil?
                return false unless month.nil? || month.match?(/\A\d+\z/)
                return false unless day.nil? || day.match?(/\A\d+\z/)

                true
              end

              def archive_precision(month:, day:)
                return :day if day
                return :month if month

                :year
              end

              def next_archive_boundary(start_date, precision)
                {
                  year: start_date.next_year,
                  month: start_date.next_month,
                  day: start_date.next_day
                }.fetch(precision)
              end

              def iso8601_start(date)
                date.strftime('%Y-%m-%dT00:00:00Z')
              end

              def parse_archive_segment(value, minimum, maximum)
                return nil unless value&.match?(/\A\d+\z/)

                number = value.to_i
                return nil if number < minimum || number > maximum

                number
              end
            end
          end
        end
      end
    end
  end
end
