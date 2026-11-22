# frozen_string_literal: true

module Html2rss
  module LinkDestination
    # Classifies visible anchor text for utility, recommendation and read-more chrome. The terms are
    # {Vocabulary}'s (en, de, fr, es, it, nl, pl, sv and ja); this owns how each concept is read: a whole
    # text, a prefix, or a whole text with its topic.
    class TextClassifier
      # Prefix labels that usually identify navigation or subscription links.
      UTILITY_PREFIX_PATTERN = /\A\s*(#{Vocabulary.alternation(:utility_prefix)})\b/ix
      # Short labels that usually identify non-article navigation links, recommendation labels included.
      UTILITY_PATTERN = /\A\s*(#{Vocabulary.alternation(:utility)}|#{Vocabulary.alternation(:recommended)})\b/ix
      # Labels for recommendation chrome rather than source articles.
      RECOMMENDED_PATTERN = /\A\s*(#{Vocabulary.alternation(:recommended)})\b/ix

      # Whole read-more labels that stand alone ("Continue reading", "Lire la suite", "続きを読む").
      READ_MORE_PHRASE = /#{Vocabulary.alternation(:read_more)}/ix
      # "More about X" lead-ins: a read-more phrase or a bare "more", then a topic preposition.
      READ_MORE_TOPIC_LEAD = /
        (?:#{READ_MORE_PHRASE.source}|#{Vocabulary.alternation(:topic_lead)})
        \s+(?:#{Vocabulary.alternation(:topic_preposition)})
      /ix
      # A read-more label as a whole text, optionally wrapped in punctuation or arrows. The topic after a
      # lead-in counts only when quoted ("More about «X»", „X“, "X", 'X', 「X」), so a headline that merely
      # opens with one ("Mehr über die Zukunft der Rente") stays a headline; Japanese topic forms put the
      # topic first.
      READ_MORE_PATTERN = /
        \A[\s\p{P}\p{S}]*(?:
          (?:#{READ_MORE_PHRASE.source})|
          (?:#{READ_MORE_TOPIC_LEAD.source})\s*[«„"“”'‘’‹「].+[»"“”'’›」]|
          \S{1,40}(?:#{Vocabulary.alternation(:read_more_suffix)})
        )[\s\p{P}\p{S}]*\z
      /ix

      # Visible new-window notice that trails a link label, in parentheses or brackets.
      NEW_WINDOW_NOTICE = /
        \s*[(\[（【]\s*(?:#{Vocabulary.alternation(:new_window_notice)})\s*[)\]）】]\s*\z
      /ix

      # @param memoize [Boolean] remember normalized texts for this instance; opt in only for an instance
      #   scoped to one extraction, never for a shared constant
      def initialize(memoize: false)
        @normalized = {} if memoize
      end

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text matches a utility label
      def utility?(text) = normalize(text).match?(UTILITY_PATTERN)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text begins with a utility label
      def utility_prefix?(text) = normalize(text).match?(UTILITY_PREFIX_PATTERN)

      # @param text [String, #to_s] visible anchor text
      # @return [Boolean] true when text identifies recommendation chrome
      def recommended?(text) = normalize(text).match?(RECOMMENDED_PATTERN)

      # @param text [String, #to_s] visible anchor text or extracted title
      # @return [Boolean] true when the whole text is a read-more label, bare or with its topic
      def read_more?(text) = normalize(text).match?(READ_MORE_PATTERN)

      private

      # Every label is read in NFC, so a decomposed accent matches the precomposed vocabulary, and without
      # its trailing new-window notice ("(opens in new tab)").
      def normalize(text)
        string = text.to_s
        return compute_normal(string) unless @normalized

        @normalized[string] ||= compute_normal(string)
      end

      def compute_normal(string) = string.unicode_normalize(:nfc).sub(NEW_WINDOW_NOTICE, '')
    end
  end
end
