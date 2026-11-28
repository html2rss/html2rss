# frozen_string_literal: true

require 'date'

module Html2rss
  class AutoSource
    module ArticleRules
      ##
      # Sole owner of "publication date from an article URL path". It is applied once, on the final
      # article, only when no other date source filled +published_at+. Precision over recall.
      #
      # Algorithm adapted from newspaper4k's DATE_REGEX (MIT), tightened to two shapes, each year-first,
      # starting a path segment and followed by a non-empty slug: +/YYYY/M/D/slug+ (day is its own segment)
      # and +YYYY-MM-DD-slug+ or +YYYY_MM_DD/slug+ (one in-segment separator, two-digit month and day).
      # Numeric ids (+58201224+), day-less paths (+/2020/06/88083+), bare +/2024/01/01/+,
      # +sku-2023-10-15-blue+, WordPress +/2024/05/10-best-laptops+ and CalVer +/docs/2024.1.2-notes+
      # therefore yield nothing. The result is day precision: midnight in the channel time zone.
      #
      # Accepted residual: evergreen or past-event pages whose path carries a date get that date, since
      # a path cannot tell publication from event date.
      module UrlDate
        # Calendar-year rule (bounded, 1995..today), unlike PathClassifier::YEARISH_SEGMENT's routing shape.
        # Earliest year accepted as a publication year.
        MIN_YEAR = 1995
        # A whole segment that is a plausible-looking four-digit year.
        YEAR = /\A(?:19|20)\d{2}\z/
        # A whole segment of one or two digits (month or day).
        DAY = /\A\d{1,2}\z/
        # One segment +YYYY-MM-DD+ or +YYYY_MM_DD+ (same separator), then +-+/+_+ and a slug, or its end
        # (a later segment must then be the slug).
        JOINED = /\A((?:19|20)\d{2})([-_])(\d{2})\2(\d{2})(?:[-_].|(\z))/m

        class << self
          ##
          # @param url [Html2rss::Url, String, nil] article URL (only its path is read)
          # @param time_zone [String] channel time zone
          # @param now [Time] the current time, which bounds a plausible date
          # @return [DateTime, nil] local midnight of the one unambiguous path date
          def call(url, time_zone:, now:)
            dates = path_dates(Url.from_absolute(url).decoded_path_segments, time_zone:, now:)
            return unless dates.one?

            Date.at_midnight(dates.first, time_zone:)
          rescue Url::InvalidUrlError
            nil
          end

          private

          def path_dates(segments, time_zone:, now:)
            latest = Date.local_today(time_zone:, now:) + 1
            candidates = segments.each_index.filter_map { candidate(segments.drop(_1)) }
            candidates.map { plausible(_1.map(&:to_i), latest) }.uniq
          end

          # +/YYYY/M/D/slug+ is four consecutive segments; the joined shape is one segment, so a decoded
          # +%2F+ inside a segment never makes a boundary.
          def candidate(segments)
            case segments
            in [YEAR => year, DAY => month, DAY => day, _, *] then [year, month, day]
            in [segment, *rest] if (match = JOINED.match(segment)) && (!match[5] || rest.any?)
              match.values_at(1, 3, 4)
            else
              nil
            end
          end

          # A path with any implausible or second distinct date is ambiguous, so nil stays in the list.
          def plausible(parts, latest)
            return unless ::Date.valid_date?(*parts)

            date = ::Date.new(*parts)
            date if date.year >= MIN_YEAR && date <= latest
          end
        end
      end
    end
  end
end
