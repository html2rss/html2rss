# frozen_string_literal: true

module Html2rss
  module Vocabulary
    # Path words that are not language vocabulary: structural page parts (menu, sidebar) and commercial
    # topics (casino, vpn, dating) that mark a destination as page chrome whatever the page's language. They
    # are not part of any language in {SHARED_LANGUAGES}.
    module NonTranslated
      # Structural page-part words.
      STRUCTURAL = Set.new(
        %w[menu sidebar widget social modal popup banner promo ad ads related recommendation recommendations
           pagination pager]
      ).freeze
      # Commercial and comparison-site topic words.
      COMMERCIAL = Set.new(
        %w[dating jobs job career careers deals deal shopping shop trading broker versicherung tierversicherung
           insurance vergleich comparison partnerboerse singleboerse krypto crypto casinos casino kreditkarten
           kreditkarte kredit echtgeld vpn kaufberater leasing]
      ).freeze
      # Both groups: the words added to a language's chrome words.
      PATH = (STRUCTURAL | COMMERCIAL).freeze
    end
  end
end
