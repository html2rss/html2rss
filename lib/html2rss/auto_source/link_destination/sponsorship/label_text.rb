# frozen_string_literal: true

module Html2rss
  class AutoSource
    module LinkDestination
      module Sponsorship
        ##
        # How sponsorship label text is read, over {Vocabulary}'s terms ({Vocabulary::LANGUAGES}), in
        # two kinds. A paid phrase states paid content; an ad word names an ad and also something editorial
        # (the advertising trade; "Promoted" a team or a person moving up). "Provided by" attribution ("提供")
        # is in neither: it also credits wire and content partners. Only whole texts match; {Sponsorship}
        # decides where a text is read.
        module LabelText
          # The matchers of one page scope, built at load.
          Readings = Data.define(:label, :element_label, :element_label_word)

          # A whole label, optionally wrapped in punctuation or separators ("Anzeige |", "[Sponsored]",
          # "Publicité:", "【広告】"), in two groups. +paid+ states paid content; +ad+ is an ad word, which also
          # names the advertising trade. Paid attribution ("Sponsored by …") may name the sponsor in up to five
          # words. Texts are read in NFC, so a decomposed accent matches too, and without bidi marks.
          LABEL_PATTERN = lambda do |paid, ad|
            /
              \A[\s\u00A0\p{P}|]*(?:(?<paid>#{paid})|
              (?<ad>#{ad}))[\s\u00A0\p{P}|]*\z
            /ix
          end
          # An element label as a whole uppercase element text ("PR", a Japanese paid-content badge). Only
          # element text counts: never an ARIA label, a heading or a topic chip, and never "Pr" or "pr".
          ELEMENT_LABEL = ->(alternation) { /\A[\s\u00A0\p{P}|]*(?:#{alternation})[\s\u00A0\p{P}|]*\z/ }

          class << self
            ##
            # @param own [Hash{Symbol => String}] a scope's own alternatives per concept
            # @return [Readings] the shared terms of every language, widened by the own ones (whole labels, like
            #   every term here)
            def build(own)
              element = Vocabulary.union(:element_label, own)
              label = LABEL_PATTERN.call(Vocabulary.union(:paid_label, own), Vocabulary.union(:ad_word, own))
              Readings.new(label:,
                           element_label: ELEMENT_LABEL.call(element), element_label_word: /#{element}/)
            end

            ##
            # @param text [String, nil] a whole text
            # @param vocabulary [Vocabulary::Scope] the page language's scope
            # @return [Symbol, nil] +:paid_label+ for a paid phrase, +:label+ for an ad word, else nil
            def kind(text, vocabulary:)
              kind_in(BY_SCOPE.fetch(vocabulary.code), text, true)
            end

            ##
            # Like {.kind} for an attribute value, where the element-only "PR" does not count.
            #
            # @param text [String, nil] a whole text
            # @param vocabulary [Vocabulary::Scope] the page language's scope
            # @return [Symbol, nil] +:paid_label+ for a paid phrase, +:label+ for an ad word, else nil
            def attribute_kind(text, vocabulary:)
              kind_in(BY_SCOPE.fetch(vocabulary.code), text, false)
            end

            ##
            # @param text [String, nil] a whole text
            # @param vocabulary [Vocabulary::Scope] the page language's scope
            # @return [Boolean] whether +text+ states paid content only through a term of a page-only language
            def own_paid?(text, vocabulary:)
              kind_in(BY_SCOPE.fetch(vocabulary.code), text, true) == :paid_label &&
                kind_in(SHARED, text, true) != :paid_label
            end

            ##
            # Cheap filter for the direct text of every node: whether it may hold a label at all.
            #
            # @param text [String]
            # @param vocabulary [Vocabulary::Scope] the page language's scope
            # @return [Boolean]
            def candidate?(text, vocabulary:)
              reading = BY_SCOPE.fetch(vocabulary.code)
              text = StringUtil.strip_bidi(text.unicode_normalize)
              text.match?(reading.label) || text.match?(reading.element_label_word)
            end

            private

            def kind_in(reading, text, element)
              return if text.nil?

              text = StringUtil.strip_bidi(text.unicode_normalize)
              return :label if element && text.match?(reading.element_label)

              match = reading.label.match(text)
              match && (match[:paid] ? :paid_label : :label)
            end
          end

          # Per scope code; scopes with the same own terms share one entry.
          BY_SCOPE = Vocabulary.by_own_terms(%i[paid_label ad_word element_label]) { |own, _scope| build(own) }
          # The reading of a scope without own terms.
          SHARED = BY_SCOPE.fetch(:all)
          private_constant :LABEL_PATTERN, :ELEMENT_LABEL, :BY_SCOPE, :SHARED
        end
      end
    end
  end
end
