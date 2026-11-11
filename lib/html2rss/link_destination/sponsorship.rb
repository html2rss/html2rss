# frozen_string_literal: true

module Html2rss
  module LinkDestination
    ##
    # Explicit sponsorship markers on SST nodes, in two kinds:
    #
    # - +:container+: a +rel+ containing +sponsored+, a truthy +data-sponsored+ or
    #   +data-advertorial+, a sponsored or advertorial class token (BEM variants included), or an
    #   ARIA label that is an ad label. The publisher states that the element is paid content.
    # - +:label+: an ad-label class token (+ad-label+, +ad-badge__item+), or a standalone element
    #   whose whole text is an ad label from a small closed multilingual set (en, de, fr, es).
    #
    # A class marker counts only on a visible, non-empty element (an empty template slot is not a
    # label). A text label never counts inside running text: anchor text and headings are never
    # read, nor are words inside an anchor, a heading, a topic chip (category, tag or kicker class)
    # or an inline element of text-bearing prose. A headline about advertising is not a marker.
    #
    # Markers only; {AutoSource::PageLinks} scopes a marker to the card that holds it.
    module Sponsorship
      # +rel+ token a publisher sets on paid links.
      REL_TOKEN = 'sponsored'
      # Attribute names that mark a sponsored element when set to a value in {ON_VALUES}.
      ATTRIBUTE_NAMES = %w[data-sponsored data-advertorial].freeze
      # Attribute values (case-insensitive) that switch a marker attribute on. Anything else is
      # off: an empty value (template output or a bare attribute; HTML parsing cannot tell them
      # apart), +no+, +null+, +false+, +0+, +off+.
      ON_VALUES = Set['true', '1', 'yes'].freeze
      # Literal substrings every {SPONSORED_CLASS} token holds; checked before the regex.
      SPONSORED_STEMS = %w[sponsored advertorial].freeze
      # Sponsored class token: whole, behind a BEM block (+card--sponsored+, +teaser__advertorial+)
      # or an +is-+/+has-+ state prefix, with an optional content suffix (+sponsored-content+).
      # +unsponsored+ and +non-sponsored+ do not match.
      SPONSORED_CLASS = /
        \A(?:[a-z0-9_-]*(?:--|__))?(?:is-|has-)?(?:sponsored|advertorial)
        (?:[-_](?:content|post|story|article|card|item|teaser))?\z
      /x
      # Ad-label class token family, with an optional BEM element or modifier: +ad-label+,
      # +ad-labels__item+, +ad-badge+, +ad-marker--small+. Ad slots (+ad-container+) are not labels.
      AD_LABEL_CLASS = /\Aad-(?:labels?|badge|marker)(?:(?:__|--)[a-z0-9-]+)?\z/
      # Literal prefix every {AD_LABEL_CLASS} token holds; checked before the regex.
      AD_LABEL_STEMS = %w[ad-].freeze
      # ARIA attributes read as labels.
      ARIA_NAMES = %w[aria-label aria-roledescription].freeze
      # Inline style that hides an element.
      HIDDEN_STYLE = /display\s*:\s*none/i
      # Class-token words (split on +-+/+_+) of topic chips, whose text names a topic, not a sale.
      CHIP_WORDS = Set['category', 'categories', 'tag', 'tags', 'kicker', 'topic', 'topics', 'rubric', 'rubrik',
                       'eyebrow'].freeze
      # Inline elements: a label inside one belongs to the surrounding text.
      PHRASING_NAMES = Set[:span, :em, :strong, :b, :i, :q, :small, :mark, :u, :s, :cite, :abbr, :time, :sup,
                           :sub, :label, :font].freeze
      # A whole label, optionally wrapped in punctuation or separators ("Anzeige |", "[Sponsored]",
      # "Publicité:"). Attribution forms may name the sponsor in up to five words.
      LABEL_PATTERN = /
        \A[[:space:]\p{P}|]*(?:
          # English
          sponsored(?:[[:space:]]+(?:content|post|story))?|advertisement|advertorial|
          (?:paid|partner)[[:space:]]+content|paid[[:space:]]+post|promoted|ad|
          # German
          anzeige|werbung|gesponsert|
          # French
          publicit[eé]|(?:contenu[[:space:]]+)?sponsoris[eé]|publireportage|
          # Spanish
          publicidad|(?:contenido[[:space:]]+)?patrocinado|publirreportaje|
          # Attribution: "Sponsored by …", "Präsentiert von …", "En partenariat avec …"
          (?:
            (?:sponsored|presented)[[:space:]]+by|pr[äa]sentiert[[:space:]]+von|
            in[[:space:]]+kooperation[[:space:]]+mit|sponsoris[eé][[:space:]]+par|
            en[[:space:]]+partenariat[[:space:]]+avec|patrocinado[[:space:]]+por
          )(?:[[:space:]]+[^[:space:]]+){0,5}
        )[[:space:]\p{P}|]*\z
      /ix

      class << self
        ##
        # @param node [SST::Node]
        # @param ancestors [Array<SST::Node>] +node+'s ancestors, root first
        # @return [Symbol, nil] +:container+ or +:label+ when +node+ itself carries an explicit
        #   sponsorship marker, else nil
        def marker(node, ancestors)
          attrs = node.attrs
          return :container if raw_marker?(attrs.raw) || class_marker?(node, SPONSORED_CLASS, SPONSORED_STEMS)
          return :label if class_marker?(node, AD_LABEL_CLASS, AD_LABEL_STEMS) || text_label?(node, ancestors)

          nil
        end

        private

        def class_marker?(node, pattern, stems)
          node.attrs.class_names.any? { |token| stems.any? { token.include?(_1) } && token.match?(pattern) } &&
            visible?(node)
        end

        def visible?(node)
          attrs = node.attrs
          (node.children.any? || node.own_text.match?(/\S/)) &&
            !attrs.raw['aria-hidden']&.casecmp?('true') && !attrs.style&.match?(HIDDEN_STYLE)
        end

        # Most nodes carry no raw attributes, so the empty check skips every lookup.
        def raw_marker?(raw)
          return false if raw.empty?

          sponsored_rel?(raw['rel']) ||
            ATTRIBUTE_NAMES.any? { ON_VALUES.include?(raw[_1]&.strip&.downcase) } ||
            ARIA_NAMES.any? { label?(raw[_1]) }
        end

        def sponsored_rel?(rel)
          return false unless rel

          rel.downcase.split.include?(REL_TOKEN)
        end

        # The own-text check runs first: it is the cheap filter for every node of the page.
        def text_label?(node, ancestors)
          label?(node.own_text) && !inert?(node) && label?(node.visible_text) &&
            ancestors.none? { _1.name == :a || _1.heading? } && !in_running_text?(ancestors)
        end

        def inert?(node) = node.name == :a || node.heading? || chip?(node)

        def chip?(node)
          node.attrs.class_names.any? { |token| token.downcase.split(/[-_]+/).any? { CHIP_WORDS.include?(_1) } }
        end

        # Climbs inline ancestors up to the first block one: prose in any of them, or a chip class on
        # an inline one, makes the label part of the surrounding text. Block classes are not read
        # (post classes such as +category-news+ sit on whole cards).
        def in_running_text?(ancestors)
          ancestors.reverse_each do |ancestor|
            return true if ancestor.own_text.match?(/\p{Alnum}/)
            return false unless PHRASING_NAMES.include?(ancestor.name)
            return true if chip?(ancestor)
          end
          false
        end

        def label?(text) = text&.match?(LABEL_PATTERN)
      end
    end
  end
end
