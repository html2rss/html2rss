# frozen_string_literal: true

module Html2rss
  # One owner for the wire rule "a value is a non-blank String, else nil".
  #
  # Names mirror ActiveSupport without depending on it. A String is blank when empty or whitespace-only.
  # Unlike ActiveSupport, every non-String is blank, `1` included.
  module StringUtil
    class << self
      # @param value [Object] wire value
      # @return [Boolean] true unless value is a String with content
      def blank?(value) = !value.is_a?(String) || value.strip.empty?

      # @param value [Object] wire value
      # @return [Boolean] true when value is a String with content
      def present?(value) = !blank?(value)

      # @param value [Object] wire value
      # @return [String, nil] value unchanged (not stripped) when present, else nil; unlike ActiveSupport,
      #   nil for any non-String
      def presence(value) = (value if present?(value))
    end
  end
end
