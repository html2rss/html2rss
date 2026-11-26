# frozen_string_literal: true

module Html2rss
  ##
  # The curation verbs behind the CLI, MCP and facade: inspect, recon, capture, test and apply, plus
  # their batch variants. Each verb owns its domain object; {Html2rss::CLI} and {Html2rss::MCP} only
  # render them. Fetching, extraction and feed building stay below, in the pipeline and AutoSource.
  module Curation
  end
end
