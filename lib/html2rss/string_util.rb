# frozen_string_literal: true

module Html2rss
  # One owner for the wire rule "a value is a non-blank String, else nil".
  #
  # Names mirror ActiveSupport without depending on it. A String is blank when empty or whitespace-only
  # (`strip: false`: only when empty). Unlike ActiveSupport, every non-String is blank, `1` included.
  module StringUtil
    class << self
      # @param value [Object] wire value
      # @param strip [Boolean] whether whitespace-only counts as blank
      # @return [Boolean] true unless value is a String with content
      def blank?(value, strip: true) = !value.is_a?(String) || (strip ? value.strip : value).empty?

      # @param value [Object] wire value
      # @param strip [Boolean] whether whitespace-only counts as blank
      # @return [Boolean] true when value is a String with content
      def present?(value, strip: true) = !blank?(value, strip:)

      # @param value [Object] wire value
      # @param strip [Boolean] whether whitespace-only counts as blank
      # @return [String, nil] value unchanged (not stripped) when present, else nil; unlike ActiveSupport,
      #   nil for any non-String
      def presence(value, strip: true) = (value if present?(value, strip:))
    end
  end
end
