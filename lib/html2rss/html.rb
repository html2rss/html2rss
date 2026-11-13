# frozen_string_literal: true

module Html2rss
  ##
  # DOM helpers for navigating and extracting from HTML trees.
  module Html
    # Raised when an extractor is built without the node or segment it extracts from.
    class InvalidError < Html2rss::ContractError; end
  end
end
