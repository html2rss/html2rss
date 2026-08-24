# frozen_string_literal: true

module Html2rss
  module FeedResolution
    ##
    # Wire-safe diagnostics for one entry-resolution attempt (Status / Marshal edge).
    Diag = Data.define(:applied, :probe_count, :reason, :winner_score) do
      ##
      # @param result [Html2rss::FeedResolution::Result]
      # @return [Diag]
      def self.from_result(result)
        new(
          applied: result.applied,
          probe_count: result.probe_count,
          reason: result.reason,
          winner_score: result.winner_score
        )
      end

      ##
      # @return [Hash{Symbol => Object}]
      def to_h
        {
          applied:,
          probe_count:,
          reason:,
          **(winner_score.nil? ? {} : { winner_score: })
        }
      end
    end
  end
end
