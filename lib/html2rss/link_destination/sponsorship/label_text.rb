# frozen_string_literal: true

module Html2rss
  module LinkDestination
    module Sponsorship
      ##
      # How sponsorship label text is read, over {Vocabulary}'s terms (en, de, fr, es, it, nl, pl, sv, ja), in
      # two kinds. A paid phrase states paid content; an ad word names an ad and also something editorial
      # (the advertising trade; "Promoted" a team or a person moving up). "Provided by" attribution ("提供")
      # is in neither: it also credits wire and content partners. Only whole texts match; {Sponsorship}
      # decides where a text is read.
      module LabelText
        # A whole label, optionally wrapped in punctuation or separators ("Anzeige |", "[Sponsored]",
        # "Publicité:", "【広告】"), in two groups. +paid+ states paid content; +ad+ is an ad word, which also
        # names the advertising trade. Paid attribution ("Sponsored by …") may name the sponsor in up to five
        # words. Texts are read in NFC, so a decomposed accent matches too.
        LABEL_PATTERN = /
          \A[\s\u00A0\p{P}|]*(?:(?<paid>#{Vocabulary.alternation(:paid_label)})|
          (?<ad>#{Vocabulary.alternation(:ad_word)}))[\s\u00A0\p{P}|]*\z
        /ix
        # An element label as a whole uppercase element text ("PR", a Japanese paid-content badge). Only
        # element text counts: never an ARIA label, a heading or a topic chip, and never "Pr" or "pr".
        ELEMENT_LABEL = /\A[\s\u00A0\p{P}|]*(?:#{Vocabulary.alternation(:element_label)})[\s\u00A0\p{P}|]*\z/
        # Whether a text holds an element label anywhere.
        ELEMENT_LABEL_WORD = /#{Vocabulary.alternation(:element_label)}/

        class << self
          ##
          # @param text [String, nil] a whole text
          # @param element [Boolean] whether +text+ is an element's text, the only place "PR" counts
          # @return [Symbol, nil] +:paid_label+ for a paid phrase, +:label+ for an ad word, else nil
          def kind(text, element: true)
            return if text.nil?

            text = text.unicode_normalize
            return :label if element && text.match?(ELEMENT_LABEL)

            match = LABEL_PATTERN.match(text)
            match && (match[:paid] ? :paid_label : :label)
          end

          ##
          # Cheap filter for the direct text of every node: whether it may hold a label at all.
          #
          # @param text [String]
          # @return [Boolean]
          def candidate?(text)
            text = text.unicode_normalize
            text.match?(LABEL_PATTERN) || text.match?(ELEMENT_LABEL_WORD)
          end
        end
      end
    end
  end
end
