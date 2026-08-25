# frozen_string_literal: true

module Html2rss
  ##
  # Immutable entry vs effective scrape URLs for one pipeline run.
  #
  # Replaces mutating {Config#scrape_url=} after {FeedResolution} rewrites the fetch URL.
  ScrapeTarget = Data.define(:entry_url, :effective_url) do
    ##
    # @param config [Html2rss::Config]
    # @return [ScrapeTarget]
    def self.from_config(config)
      entry = config.url
      new(entry_url: entry, effective_url: entry)
    end

    ##
    # @param url [String, Html2rss::Url]
    # @return [ScrapeTarget]
    def with_effective(url)
      self.class.new(entry_url:, effective_url: Url.from_absolute(url).to_s)
    end
  end
end
