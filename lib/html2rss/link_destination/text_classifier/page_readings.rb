# frozen_string_literal: true

module Html2rss
  module LinkDestination
    class TextClassifier
      ##
      # Owner of how the call-to-action, read-more and new-window concepts ({Vocabulary::PAGE_PATTERNS}) are read:
      # one precompiled set of matchers per page scope, built at load. The shared terms are every language of
      # {Vocabulary::ALL}; a {Vocabulary::PAGE_ONLY} language adds its own, read as whole labels only, so a Han
      # term never opens a headline. Scopes with the same own terms (every shared language and +:all+ have none)
      # share one entry, compiled once, so a scope without own terms reads exactly the shared terms.
      module PageReadings
        # A sentence-form call to action ("Subscribe to our newsletter", "Abonnieren Sie unseren Newsletter"): a
        # multi-word imperative phrase at the start of the text, read in every language. An infinitive or noun
        # form stays a headline opener ("Kommentare zum Artikel 13: ..."), so the vocabulary lists it only with a
        # chrome object or as the whole label. A Latin term ends at a word boundary. A Japanese term has none
        # between two kana or kanji, so it ends at whitespace, punctuation, a symbol or the end of the text
        # ("コメントを投稿した男性を逮捕" is a headline).
        UTILITY_CTA = /
          \A\s*(?:#{Vocabulary.alternation(:utility_cta)})
          (?:(?<![\p{Han}\p{Hiragana}\p{Katakana}])\b|(?<=[\p{Han}\p{Hiragana}\p{Katakana}])(?=[\s\p{P}\p{S}]|\z))
        /iux

        # The concepts of the read-more matcher: whole read-more labels that stand alone ("Continue reading",
        # "Lire la suite", "続きを読む"); "More about X" lead-ins (a read-more phrase or a bare "more", then a topic
        # preposition); a read-more label as a whole text, optionally wrapped in punctuation or arrows. The topic
        # after a lead-in counts only when quoted ("More about «X»", „X“, "X", 'X', 「X」), so a headline that
        # merely opens with one ("Mehr über die Zukunft der Rente") stays a headline; Japanese topic forms put
        # the topic first.
        READ_MORE_CONCEPTS = %i[read_more topic_lead topic_preposition read_more_suffix].freeze

        # Visible new-window notice that trails a link label, in parentheses or brackets.
        NEW_WINDOW = ->(alternation) { /\s*[(\[（【]\s*(?:#{alternation})\s*[)\]）】]\s*\z/ix }

        READ_MORE = lambda do |phrase, lead, preposition, suffix|
          /
            \A[\s\p{P}\p{S}]*(?:
              (?:#{phrase})|
              (?:(?:#{phrase}|#{lead})\s+(?:#{preposition}))\s*[«„"“”'‘’‹「].+[»"“”'’›」]|
              \S{1,40}(?:#{suffix})
            )[\s\p{P}\p{S}]*\z
          /ix
        end

        class << self
          ##
          # @param own [Hash{Symbol => String}] a scope's own alternatives per {Vocabulary::PAGE_PATTERNS} concept
          # @return [Hash{Symbol => Regexp}] +:cta+ (the shared call to action), +:own_cta+ (the own terms as whole
          #   labels), +:read_more+ and +:new_window+ (the shared terms widened by the own ones)
          def build(own)
            union = ->(concept) { [Vocabulary.alternation(concept), own.fetch(concept)].reject(&:empty?).join('|') }
            {
              cta: UTILITY_CTA,
              own_cta: TextClassifier.whole_label([own.fetch(:utility_cta)]),
              read_more: READ_MORE.call(*READ_MORE_CONCEPTS.map(&union)),
              new_window: NEW_WINDOW.call(union.call(:new_window_notice))
            }.freeze
          end
        end

        # Per scope code; scopes with the same own terms share one entry.
        BY_SCOPE = begin
          built = {}
          Vocabulary::SCOPES.transform_values do |scope|
            own = Vocabulary::PAGE_PATTERNS.to_h { [_1, scope.own_alternation(_1)] }
            built[own] ||= build(own)
          end.freeze
        end
        private_constant :UTILITY_CTA, :READ_MORE_CONCEPTS, :NEW_WINDOW, :READ_MORE
      end
    end
  end
end
