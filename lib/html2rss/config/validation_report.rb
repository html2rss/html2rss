# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Public result of config validation. Dry::Validation::Result never crosses this boundary.
    # +success+ is derived from +issues+ — invalid states like +success: true+ with issues cannot exist.
    ValidationReport = Data.define(:issues) do
      ##
      # @return [Html2rss::Config::ValidationReport]
      def self.ok
        new(issues: [].freeze)
      end

      ##
      # @param issues [Array<Html2rss::Config::ValidationIssue>]
      # @return [Html2rss::Config::ValidationReport]
      def self.failure(issues)
        new(issues: Array(issues).freeze)
      end

      ##
      # @param issues [Array<Html2rss::Config::ValidationIssue>]
      def initialize(issues:)
        super(issues: Array(issues).freeze)
      end

      # @return [Boolean]
      def success? = issues.empty?

      # @return [Boolean]
      def failure? = !success?

      ##
      # Wire shape: +{ success:, issues: [...] }+ only (MCP contract v3).
      #
      # @return [Hash{Symbol => Object}]
      def to_h
        { success: success?, issues: issues.map(&:to_h) }
      end

      ##
      # Human-readable summary for CLI / exception messages.
      #
      # @return [String]
      def to_s
        return 'valid' if success?

        issues.map(&:to_s).join('; ')
      end
    end
  end
end
