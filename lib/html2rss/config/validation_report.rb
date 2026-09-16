# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Public result of config validation. Dry::Validation::Result never crosses this boundary.
    ValidationReport = Data.define(:success, :issues) do
      ##
      # @return [Html2rss::Config::ValidationReport]
      def self.ok
        new(success: true, issues: [].freeze)
      end

      ##
      # @param issues [Array<Html2rss::Config::ValidationIssue>]
      # @return [Html2rss::Config::ValidationReport]
      def self.failure(issues)
        new(success: false, issues: Array(issues).freeze)
      end

      ##
      # @param success [Boolean]
      # @param issues [Array<Html2rss::Config::ValidationIssue>]
      def initialize(success:, issues:)
        super(success:, issues: Array(issues).freeze)
      end

      # @return [Boolean]
      def success? = success

      # @return [Boolean]
      def failure? = !success

      ##
      # Wire shape: +{ success:, issues: [...] }+ only.
      #
      # @return [Hash{Symbol => Object}]
      def to_h
        { success:, issues: issues.map(&:to_h) }
      end
    end
  end
end
