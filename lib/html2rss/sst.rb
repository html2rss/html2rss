# frozen_string_literal: true

module Html2rss
  ##
  # Simplified Semantic Tree namespace for the heuristic auto-source pipeline.
  module SST
    # Raised when a tree node, attrs, text or document is built from invalid parts.
    class InvalidError < Html2rss::ContractError; end
  end
end
