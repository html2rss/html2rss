# frozen_string_literal: true

module Html2rss
  class AutoSource
    module Scraper
      ##
      # Card/list discovery helpers used by AutoSource scrapers before field extraction.
      #
      # Html2rss::Html::Extractors fills article fields from a container; discovery finds those containers.
      #
      # Anchorless work has two distinct jobs under the historical scraper option
      # +:fallback_anchorless+ — see {Discovery::Anchorless}.
      module Discovery
      end
    end
  end
end
