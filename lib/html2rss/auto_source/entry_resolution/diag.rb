# frozen_string_literal: true

module Html2rss
  class AutoSource
    module EntryResolution
      Diag = Data.define(:applied, :probe_count, :reason, :winner_score, :out_of_scope)

      ##
      # Wire-safe diagnostics for one entry-resolution attempt (Status / Marshal edge).
      class Diag
        ##
        # @param result [Html2rss::AutoSource::EntryResolution::Result]
        # @return [Diag]
        def self.from_result(result)
          new(
            applied: result.applied,
            probe_count: result.probe_count,
            reason: result.reason,
            winner_score: result.winner_score,
            out_of_scope: result.out_of_scope
          )
        end

        ##
        # @return [Hash{Symbol => Object}]
        def to_h
          {
            applied:,
            probe_count:,
            reason:,
            **(winner_score.nil? ? {} : { winner_score: }),
            **(out_of_scope.positive? ? { out_of_scope_skipped: out_of_scope } : {})
          }
        end
      end
    end
  end
end
