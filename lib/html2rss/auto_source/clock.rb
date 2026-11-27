# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # The time of one run: the instant ({Html2rss::Extraction} input +now+) and the channel time zone, read
    # by every stage that dates an item. No stage reads the system clock.
    #
    # @!attribute now [Time] the current time
    # @!attribute time_zone [String, nil] channel time zone for naive dates (nil reads as UTC)
    Clock = Data.define(:now, :time_zone)
  end
end
