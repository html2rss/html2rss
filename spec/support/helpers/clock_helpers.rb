# frozen_string_literal: true

# A fixed run time for specs that build scrapers or extractors directly.
module ClockHelpers
  SPEC_NOW = Time.utc(2026, 11, 20, 12)

  # @param time_zone [String, nil]
  # @return [Html2rss::AutoSource::Clock]
  def clock_for(time_zone = 'UTC') = Html2rss::AutoSource::Clock.new(now: SPEC_NOW, time_zone:)
end
