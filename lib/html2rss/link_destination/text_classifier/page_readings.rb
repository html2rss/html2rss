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

        # Visible new-window notice that trails a link label, in parentheses or brackets.
        NEW_WINDOW = ->(alternation) { /\s*[(\[（【]\s*(?:#{alternation})\s*[)\]）】]\s*\z/ix }

        # The read-more matcher: whole read-more labels that stand alone ("Continue reading", "Lire la suite",
        # "続きを読む"); "More about X" lead-ins (a read-more phrase or a bare "more", then a topic preposition); a
        # read-more label as a whole text, optionally wrapped in punctuation or arrows. The topic after a lead-in
        # counts only when quoted ("More about «X»", „X“, "X", 'X', 「X」), so a headline that merely opens with one
        # ("Mehr über die Zukunft der Rente") stays a headline; Japanese topic forms put the topic first.
        #
        # The own read-more terms (+standalone+) are whole labels only: the topic lead-in reads the shared +phrase+, so
        # a Chinese label never opens a quoted-topic form ("阅读全文 about “气候”" is a headline).
        READ_MORE = lambda do |standalone, phrase, lead, preposition, suffix|
          /
            \A[\s\p{P}\p{S}]*(?:
              (?:#{standalone})|
              (?:(?:#{phrase}|#{lead})\s+(?:#{preposition}))\s*[«„"“”'‘’‹「].+[»"“”'’›」]|
              \S{1,40}(?:#{suffix})
            )[\s\p{P}\p{S}]*\z
          /ix
        end

        class << self
          ##
          # @param own [Hash{Symbol => String}] a scope's own alternatives per {Vocabulary::PAGE_PATTERNS} concept
          # @return [Hash{Symbol => Regexp}] +:cta+ (the shared call to action), +:own_cta+, +:list_more+ and
          #   +:own_more+ (the own call-to-action, list-level and read-more plus list-level terms as whole labels,
          #   bare or with a bracketed count), +:read_more+ and +:new_window+ (the shared terms widened by the own
          #   read-more ones)
          def build(own)
            union = ->(concept) { Vocabulary.union(concept, own) }
            {
              cta: UTILITY_CTA,
              own_cta: TextClassifier.whole_label([own.fetch(:utility_cta)]),
              list_more: TextClassifier.whole_label([own.fetch(:list_more)]),
              own_more: TextClassifier.whole_label(own.values_at(:read_more, :list_more)),
              read_more: READ_MORE.call(union.call(:read_more), Vocabulary.alternation(:read_more),
                                        *%i[topic_lead topic_preposition read_more_suffix].map(&union)),
              new_window: NEW_WINDOW.call(union.call(:new_window_notice))
            }.freeze
          end
        end

        # Per scope code; scopes with the same own terms share one entry.
        BY_SCOPE = Vocabulary.by_own_terms(Vocabulary::PAGE_PATTERNS) { |own, _scope| build(own) }
        private_constant :UTILITY_CTA, :NEW_WINDOW, :READ_MORE
      end
    end
  end
end
