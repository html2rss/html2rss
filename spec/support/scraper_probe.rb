# frozen_string_literal: true

# Minimal concrete scraper for exercising {Html2rss::AutoSource::Scraper::Base} on its own.
class ScraperProbe < Html2rss::AutoSource::Scraper::Base
  def self.articles?(parsed_body) = parsed_body == :detectable

  def each(&) = [parsed_body, url].each(&)
end
