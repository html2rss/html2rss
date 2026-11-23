# frozen_string_literal: true

module Html2rss
  module LinkDestination
    module Sponsorship
      ##
      # How sponsorship label text is read, over {Vocabulary}'s terms (en, de, fr, es, it, nl, pl, sv, ja, pt), in
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
            union = ->(concept) { [Vocabulary.alternation(concept), own.fetch(concept)].reject(&:empty?).join('|') }
            Readings.new(label: LABEL_PATTERN.call(union.call(:paid_label), union.call(:ad_word)),
                         element_label: ELEMENT_LABEL.call(union.call(:element_label)),
                         element_label_word: /#{union.call(:element_label)}/)
          end

          ##
          # @param text [String, nil] a whole text
          # @param vocabulary [Vocabulary::Scope] the page language's scope
          # @param element [Boolean] whether +text+ is an element's text, the only place "PR" counts
          # @return [Symbol, nil] +:paid_label+ for a paid phrase, +:label+ for an ad word, else nil
          def kind(text, vocabulary:, element: true)
            return if text.nil?

            reading = BY_SCOPE.fetch(vocabulary.code)
            text = TextClassifier.strip_bidi(text.unicode_normalize)
            return :label if element && text.match?(reading.element_label)

            match = reading.label.match(text)
            match && (match[:paid] ? :paid_label : :label)
          end

          ##
          # Cheap filter for the direct text of every node: whether it may hold a label at all.
          #
          # @param text [String]
          # @param vocabulary [Vocabulary::Scope] the page language's scope
          # @return [Boolean]
          def candidate?(text, vocabulary:)
            reading = BY_SCOPE.fetch(vocabulary.code)
            text = TextClassifier.strip_bidi(text.unicode_normalize)
            text.match?(reading.label) || text.match?(reading.element_label_word)
          end
        end

        # Per scope code; scopes with the same own terms share one entry.
        BY_SCOPE = begin
          built = {}
          Vocabulary::SCOPES.transform_values do |scope|
            own = %i[paid_label ad_word element_label].to_h { [_1, scope.own_alternation(_1)] }
            built[own] ||= build(own)
          end.freeze
        end
        private_constant :LABEL_PATTERN, :ELEMENT_LABEL, :BY_SCOPE
      end
    end
  end
end
