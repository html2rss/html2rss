# frozen_string_literal: true

module Html2rss
  module Test
    ##
    # Pass/fail classification for a configuration test after live extraction.
    # Owns the min_items check and maps {Quality}'s failure reasons to pass/fail; {Test.call} orchestrates only.
    module Policy
      Outcome = Data.define(:passed, :failure_kind, :error_message)

      ##
      # Outcome of evaluating test thresholds.
      class Outcome
        # @return [Boolean]
        def success? = passed

        # @return [Boolean]
        def failure? = !passed
      end

      ##
      # Evaluates whether the test passed thresholds and determines any failure kind and error message.
      #
      # @param item_count [Integer]
      # @param min_items [Integer]
      # @param strict_quality [Boolean]
      # @param quality_report [QualityReport] its {QualityReport#failure_reasons} are the quality thresholds
      # @return [Outcome]
      def self.evaluate(item_count:, min_items:, strict_quality:, quality_report:)
        if item_count < min_items
          message = "Extracted #{item_count} items (minimum required: #{min_items})"
          return Outcome.new(passed: false, failure_kind: FailureKind[:min_items], error_message: message)
        end

        reasons = strict_quality ? quality_report.failure_reasons : []
        return Outcome.new(passed: true, failure_kind: nil, error_message: nil) if reasons.empty?

        Log.info("Test strict quality: failure_kind=quality item_count=#{item_count}")
        Outcome.new(passed: false, failure_kind: FailureKind[:quality],
                    error_message: "Feed quality check failed (#{reasons.join(', ')})")
      end
    end
  end
end
