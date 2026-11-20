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
      # Algorithm adapted from newspaper4k's DATE_REGEX (MIT), tightened: year-first Y/M/D, the date
      # starts a path segment and is followed by a non-empty slug (same segment after +-+ or +_+, or a later
      # segment). Numeric ids (+58201224+), day-less paths (+/2020/06/88083+), bare +/2024/01/01/+ and
      # +sku-2023-10-15-blue+ therefore yield nothing. The result is day precision: midnight in the
      # channel time zone.
      module UrlDate
        # Earliest year accepted as a publication year.
        MIN_YEAR = 1995
        # Segment-initial Y/M/D (separators +/ - _ .+) followed by a slug.
        YMD = %r{(?<![^/])((?:19|20)\d{2})[/\-_.](\d{1,2})[/\-_.](\d{1,2})(?=[-_][^/]|/[^/])}

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
            latest = Date.today(time_zone:) + 1
            path.scan(YMD).map { |parts| plausible(parts.map(&:to_i), latest) }.uniq
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
