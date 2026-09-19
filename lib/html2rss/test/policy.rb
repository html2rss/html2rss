# frozen_string_literal: true

module Html2rss
  module Test
    ##
    # Pass/fail classification for a configuration test after live extraction.
    # Owns min_items vs quality thresholds; {Test.call} orchestrates only.
    module Policy
      module_function

      ##
      # Outcome of evaluating test thresholds.
      Outcome = Data.define(:passed, :failure_kind, :error_message) do
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
      # @param quality_report [QualityReport]
      # @return [Outcome]
      def evaluate(item_count:, min_items:, strict_quality:, quality_report:)
        min_items_passed = item_count >= min_items
        quality_failed = strict_quality && min_items_passed && quality_failure?(quality_report)
        passed = min_items_passed && !quality_failed
        failure_kind, error_message = outcome_failure(
          min_items_passed:, quality_failed:, item_count:, min_items:, quality_report:
        )
        log_strict_quality_failure(failure_kind, item_count) if quality_failed
        Outcome.new(passed:, failure_kind:, error_message:)
      end

      def log_strict_quality_failure(failure_kind, item_count)
        Log.info("Test strict quality: failure_kind=#{failure_kind.to_sym} item_count=#{item_count}")
      end
      private_class_method :log_strict_quality_failure

      ##
      # @param quality_report [QualityReport]
      # @return [Boolean]
      def quality_failure?(quality_report)
        metrics = quality_report.metrics
        item_count = metrics[:item_count]
        return false if item_count.zero?

        duplicate_urls_failure?(metrics) || junk_title_ratio_failure?(metrics) || short_title_failure?(metrics)
      end

      ##
      # @param min_items_passed [Boolean]
      # @param quality_failed [Boolean]
      # @param item_count [Integer]
      # @param min_items [Integer]
      # @param quality_report [QualityReport]
      # @return [Array(FailureKind, nil), Array(String, nil)]
      def outcome_failure(min_items_passed:, quality_failed:, item_count:, min_items:, quality_report:)
        return [nil, nil] if min_items_passed && !quality_failed
        unless min_items_passed
          return [FailureKind.coerce(:min_items),
                  "Extracted #{item_count} items (minimum required: #{min_items})"]
        end

        [FailureKind.coerce(:quality), quality_failure_message(quality_report)]
      end

      def quality_failure_message(quality_report)
        reasons = quality_failure_reasons(quality_report.metrics)
        "Feed quality check failed (#{reasons.join(', ')})"
      end
      private_class_method :quality_failure_message

      def quality_failure_reasons(metrics)
        reasons = []
        reasons << 'duplicate_urls' if duplicate_urls_failure?(metrics)
        reasons << 'generic_titles' if junk_title_ratio_failure?(metrics)
        reasons << 'short_titles' if short_title_failure?(metrics)
        reasons
      end
      private_class_method :quality_failure_reasons

      def duplicate_urls_failure?(metrics)
        metrics[:item_count] >= 2 && metrics[:unique_url_count] < 2
      end
      private_class_method :duplicate_urls_failure?

      def junk_title_ratio_failure?(metrics)
        metrics[:junk_title_count] > (metrics[:item_count] / 2.0)
      end
      private_class_method :junk_title_ratio_failure?

      def short_title_failure?(metrics)
        metrics[:short_title_count].positive?
      end
      private_class_method :short_title_failure?
    end
  end
end
