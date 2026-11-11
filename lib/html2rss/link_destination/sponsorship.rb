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
      # Literal prefix every {AD_LABEL_CLASS} token starts with; checked before the regex.
      AD_LABEL_PREFIX = 'ad-'
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
        \A[\s\u00A0\p{P}|]*(?:
          # English
          sponsored(?:\s+(?:content|post|story))?|advertisement|advertorial|
          (?:paid|partner)\s+content|paid\s+post|promoted|ad|
          # German
          anzeige|werbung|gesponsert|
          # French
          publicit[eé]|(?:contenu\s+)?sponsoris[eé]|publireportage|
          # Spanish
          publicidad|(?:contenido\s+)?patrocinado|publirreportaje|
          # Attribution: "Sponsored by …", "Präsentiert von …", "En partenariat avec …"
          (?:
            (?:sponsored|presented)\s+by|pr[äa]sentiert\s+von|
            in\s+kooperation\s+mit|sponsoris[eé]\s+par|
            en\s+partenariat\s+avec|patrocinado\s+por
          )(?:\s+\S+){0,5}
        )[\s\u00A0\p{P}|]*\z
      /ix

      class << self
        ##
        # @param node [SST::Node]
        # @param ancestors [Array<SST::Node>] +node+'s ancestors, root first
        # @return [Symbol, nil] +:container+ or +:label+ when +node+ itself carries an explicit
        #   sponsorship marker, else nil
        def marker(node, ancestors)
          return :container if raw_marker?(node.attrs.raw)

          kind = class_marker(node.attrs.class_names)
          return (kind if visible?(node)) if kind

          :label if text_label?(node, ancestors)
        end

        private

        # Runs on every node of the page: literal checks gate each regex.
        def class_marker(class_names)
          kind = nil
          class_names.each do |token|
            return :container if sponsored_class?(token)

            kind ||= :label if token.start_with?(AD_LABEL_PREFIX) && token.match?(AD_LABEL_CLASS)
          end
          kind
        end

        def sponsored_class?(token)
          (token.include?('sponsored') || token.include?('advertorial')) && token.match?(SPONSORED_CLASS)
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
