# frozen_string_literal: true

module Html2rss
  class AutoSource
    ##
    # Card/list discovery helpers used by AutoSource scrapers before field extraction.
    #
    # Html2rss::Html::ArticleExtractor fills article fields from a container; discovery finds those containers.
    #
    # DOM list discovery for anchorless or classless pages is owned by {Discovery::DomClustering}.
    module Discovery
    end
  end
end
