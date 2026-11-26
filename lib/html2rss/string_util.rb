# frozen_string_literal: true

module Html2rss
  # One owner for the wire rule "a value is a non-blank String, else nil".
  #
  # Names mirror ActiveSupport without depending on it. A String is blank when empty or whitespace-only.
  # Unlike ActiveSupport, every non-String is blank, `1` included.
  module StringUtil
    # Direction marks and embedding/isolate controls (LRM, RLM, ALM, LRE..RLO, LRI..PDI): they render nothing and
    # change no letter, so a label ("\u200FContact\u200F") is read without them ({.strip_bidi}). Only label
    # text is read this way; extracted titles and descriptions keep them.
    BIDI_MARKS = /[\u200E\u200F\u061C\u202A-\u202E\u2066-\u2069]/
    private_constant :BIDI_MARKS

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

      # The one owner of reading a label without direction marks ({BIDI_MARKS}). Text without a mark is
      # returned as is, so the common case allocates nothing.
      #
      # @param text [String]
      # @return [String] +text+ without bidi marks
      def strip_bidi(text) = text.match?(BIDI_MARKS) ? text.gsub(BIDI_MARKS, '') : text
    end
  end
end
