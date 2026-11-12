# frozen_string_literal: true

module Html2rss
  module LinkDestination
    module Sponsorship
      ##
      # The closed multilingual vocabulary of sponsorship label text (en, de, fr, es, it, nl, pl, sv, ja), in
      # two kinds. A paid phrase states paid content; an ad word names an ad and also something editorial
      # (the advertising trade; "Promoted" a team or a person moving up). "Provided by" attribution ("提供")
      # is in neither: it also credits wire and content partners. Only whole texts match; {Sponsorship}
      # decides where a text is read.
      module LabelText
        # A whole label, optionally wrapped in punctuation or separators ("Anzeige |", "[Sponsored]",
        # "Publicité:", "【広告】"), in two groups. +paid+ states paid content; +ad+ is an ad word, which also
        # names the advertising trade. Paid attribution ("Sponsored by …") may name the sponsor in up to five
        # words.
        LABEL_PATTERN = /
          \A[\s\u00A0\p{P}|]*(?:(?<paid>
            # English
            sponsored(?:\s+(?:content|post|story))?|advertorial|(?:paid|partner)\s+content|paid\s+post|
            sponsored\s+by(?:\s+\S+){0,5}|
            # German
            gesponsert(?:\s+von(?:\s+\S+){0,5})?|
            # French
            (?:contenu\s+)?sponsoris[eé](?:\s+par(?:\s+\S+){0,5})?|publireportage|contenus?\s+partenaires?|
            # Spanish
            (?:contenido\s+)?patrocinado(?:\s+por(?:\s+\S+){0,5})?|publirreportaje|
            # Italian
            (?:contenuto\s+)?sponsorizzat[oa](?:\s+(?:da|a\s+cura\s+di)(?:\s+\S+){0,5})?|
            informazione\s+pubblicitaria|pubbliredazionale|
            # Dutch
            gesponsord(?:e\s+(?:inhoud|content))?(?:\s+door(?:\s+\S+){0,5})?|
            # Polish
            sponsorowane|materia[łl]\s+(?:sponsorowany|partnera|partnerski|promocyjny|reklamowy)|
            materia[łl]y\s+(?:sponsorowane|partnera|partnerskie|promocyjne|reklamowe)|artyku[łl]\s+sponsorowany|
            # Swedish
            sponsrad|sponsrat(?:\s+inneh[åa]ll)?|annonssamarbete|
            # Japanese
            タイアップ(?:広告|企画)?|スポンサー(?:リンク|コンテンツ)|広告企画|PR企画
          )|(?<ad>
            ad|advertisement|promoted|
            anzeige|werbung|publicit[eé]|publicidad|pubblicit[àa]|advertentie|reclame|reklama|annons|
            reklam|広告|スポンサー
          ))[\s\u00A0\p{P}|]*\z
        /ix
        # "PR" as a whole uppercase label element (a Japanese paid-content badge). Only element text counts:
        # never an ARIA label, a heading or a topic chip, and never "Pr" or "pr".
        ELEMENT_LABEL = /\A[\s\u00A0\p{P}|]*PR[\s\u00A0\p{P}|]*\z/

        class << self
          ##
          # @param text [String, nil] a whole text
          # @param element [Boolean] whether +text+ is an element's text, the only place "PR" counts
          # @return [Symbol, nil] +:paid_label+ for a paid phrase, +:label+ for an ad word, else nil
          def kind(text, element: true)
            return if text.nil?
            return :label if element && text.match?(ELEMENT_LABEL)

            match = LABEL_PATTERN.match(text)
            match && (match[:paid] ? :paid_label : :label)
          end

          ##
          # Cheap filter for the direct text of every node: whether it may hold a label at all.
          #
          # @param text [String]
          # @return [Boolean]
          def candidate?(text) = text.match?(LABEL_PATTERN) || text.include?('PR')
        end
      end
    end
  end
end
