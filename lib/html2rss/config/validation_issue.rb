# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # One structured validation finding for GUI/MCP/CLI/Test.
    #
    # +path+ is JSON-pointer-friendly segments. +code+ is closed ({CODES}).
    # +expected+ / +actual+ are JSON-ish or +nil+ (never invented).
    ValidationIssue = Data.define(:path, :code, :message, :expected, :actual) do
      # Closed set of issue codes (mapper owns Dry predicate → code).
      # rubocop:disable-next Lint/ConstantDefinitionInBlock -- Data.define type constant
      CODES = Set[
        :missing_key,
        :type_mismatch,
        :unknown_value,
        :invalid_value,
        :constraint,
        :parse
      ].freeze

      ##
      # @param path [Array<Symbol, Integer, String>]
      # @param code [Symbol]
      # @param message [String]
      # @param expected [Hash, String, Numeric, true, false, nil]
      # @param actual [Hash, String, Numeric, true, false, nil]
      def initialize(path:, code:, message:, expected: nil, actual: nil)
        raise ArgumentError, "unknown ValidationIssue code: #{code.inspect}" unless CODES.include?(code)

        super(
          path: Array(path).freeze,
          code:,
          message: message.to_s,
          expected:,
          actual:
        )
      end

      ##
      # Wire shape for a single issue.
      #
      # @return [Hash{Symbol => Object}]
      def to_h
        { path:, code:, message:, expected:, actual: }
      end
    end
  end
end
