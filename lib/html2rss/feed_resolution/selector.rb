# frozen_string_literal: true

module Html2rss
  module FeedResolution
    ##
    # Picks the highest-scoring probe result that beats the entry extract.
    module Selector
      module_function

      ##
      # @param scored [Array<Probe::Scored>]
      # @param entry_articles_count [Integer]
      # @return [Probe::Scored, nil]
      def call(scored:, entry_articles_count:)
        winner = scored.max_by(&:score)
        return unless winner
        return if winner.articles_count <= entry_articles_count.to_i
        return if winner.score <= 0

        winner
      end
    end
  end
end
