# frozen_string_literal: true

require 'date'
require 'uri'

module Html2rss
  module Html
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
        # Earliest year accepted as a publication year.
        MIN_YEAR = 1995
        # +/YYYY/M/D/slug+: the day is a whole segment, a slug segment follows.
        SLASHED = %r{(?<![^/])((?:19|20)\d{2})/(\d{1,2})/(\d{1,2})(?=/[^/])}
        # +YYYY-MM-DD+ or +YYYY_MM_DD+ (same separator), then +-+, +_+ or +/+ and a slug.
        JOINED = %r{(?<![^/])((?:19|20)\d{2})([-_])(\d{2})\2(\d{2})(?=[-_/][^/])}

        class << self
          ##
          # @param url [Html2rss::Url, String, nil] article URL (only its path is read)
          # @param time_zone [String] channel time zone
          # @return [DateTime, nil] local midnight of the one unambiguous path date
          def call(url, time_zone:)
            dates = path_dates(url, time_zone:)
            return unless dates.one?

            Date.at_midnight(dates.first, time_zone:)
          end

          private

          def path_dates(url, time_zone:)
            path = URI.parse(url.to_s).path.to_s
            latest = Date.local_today(time_zone:) + 1
            joined = path.scan(JOINED).map { |year, _separator, month, day| [year, month, day] }
            candidates = path.scan(SLASHED) + joined
            candidates.map { |parts| plausible(parts.map(&:to_i), latest) }.uniq
          rescue URI::InvalidURIError
            []
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
