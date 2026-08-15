# frozen_string_literal: true

module Html2rss
  module Scoring
    ##
    # Composite score with quality/junk split and optional typed feature breakdown.
    Score = Data.define(:composite, :quality, :junk, :breakdown)
    # Shared empty feature breakdown for scores without per-feature tallies.
    Score::EMPTY_BREAKDOWN = {}.freeze
  end
end
