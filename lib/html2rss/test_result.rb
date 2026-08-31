# frozen_string_literal: true

module Html2rss
  ##
  # Immutable value object representing the outcome of a configuration test / check operation.
  TestResult = Data.define(
    :success,
    :item_count,
    :sample_items,
    :channel_title,
    :channel_url,
    :strategy_used,
    :duration_seconds,
    :validation_errors,
    :error_message
  ) do
    ##
    # @return [Boolean] whether the schema validation succeeded
    def valid_schema?
      validation_errors.nil? || validation_errors.empty?
    end

    ##
    # @return [Boolean] whether the test extracted zero items
    def empty_feed?
      item_count.zero?
    end

    ##
    # @return [Hash{Symbol => Object}] hash representation
    def to_h # rubocop:disable Metrics/MethodLength
      {
        success:,
        item_count:,
        sample_items:,
        channel_title:,
        channel_url:,
        strategy_used:,
        duration_seconds:,
        validation_errors:,
        error_message:
      }.compact
    end
  end
end
