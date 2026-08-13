# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Discovery helpers still used outside the SST heuristic pipeline.
    #
    # {Discovery::Sitemap} remains for the sitemap scraper. Card/list discovery
    # for SemanticHtml/Html now lives in {Segmenter}.
    module Discovery
    end
  end
end
