# frozen_string_literal: true

module Html2rss
  module LinkDestination
    ##
    # Explicit sponsorship markers on SST nodes: a +rel+ containing +sponsored+, an advertorial
    # attribute or class, an ad-label class token, or an ARIA label or element text that is exactly an ad label from a
    # small closed multilingual set (en, de, fr, es). Anchor text is never read, so a headline
    # about advertising is not a marker.
    #
    # Markers only; {AutoSource::PageLinks} scopes a marker to the card that holds it.
    module Sponsorship
      # +rel+ token a publisher sets on paid links.
      REL_TOKEN = 'sponsored'
      # Attribute names whose presence marks a sponsored card (unless set to false).
      ATTRIBUTE_NAMES = %w[data-sponsored data-advertorial].freeze
      # Attribute values that switch a marker attribute off.
      OFF_VALUES = Set['false', '0'].freeze
      # Class tokens that mark a sponsored card.
      CLASS_NAMES = Set['advertorial', 'sponsored', 'sponsored-content', 'is-sponsored'].freeze
      # Ad-label class token family, with an optional BEM element or modifier: +ad-label+,
      # +ad-labels__item+, +ad-badge+, +ad-marker--small+. Ad slots (+ad-container+) are not labels.
      AD_LABEL_CLASS = /\Aad-(?:labels?|badge|marker)(?:(?:__|--)[a-z0-9-]+)?\z/
      # Literal prefix every {AD_LABEL_CLASS} token starts with; checked before the regex.
      AD_LABEL_PREFIX = 'ad-'
      # ARIA attributes read as labels.
      ARIA_NAMES = %w[aria-label aria-roledescription].freeze
      # A whole label, optionally wrapped in punctuation ("Anzeige", "[Sponsored]", "Publicité:").
      LABEL_PATTERN = /
        \A[\s\p{P}]*(?:
          # English
          sponsored(?:\s+(?:content|post|story))?|advertisement|advertorial|paid\s+(?:content|post)|promoted|
          # German
          anzeige|werbung|gesponsert|
          # French
          publicit[eé]|(?:contenu\s+)?sponsoris[eé]|publireportage|
          # Spanish
          publicidad|(?:contenido\s+)?patrocinado|publirreportaje
        )[\s\p{P}]*\z
      /ix

      class << self
        ##
        # @param node [SST::Node]
        # @return [Boolean] true when +node+ itself carries an explicit sponsorship marker
        def marker?(node)
          attrs = node.attrs
          class_marker?(attrs.class_names) || raw_marker?(attrs.raw) ||
            (node.name != :a && label?(node.own_text))
        end

        private

        def class_marker?(class_names)
          class_names.any? do |token|
            CLASS_NAMES.include?(token) || (token.start_with?(AD_LABEL_PREFIX) && token.match?(AD_LABEL_CLASS))
          end
        end

        # Most nodes carry no raw attributes, so the empty check skips every lookup.
        def raw_marker?(raw)
          return false if raw.empty?

          sponsored_rel?(raw['rel']) ||
            ATTRIBUTE_NAMES.any? { switched_on?(raw[_1]) } ||
            ARIA_NAMES.any? { label?(raw[_1]) }
        end

        def sponsored_rel?(rel)
          return false unless rel

          rel.downcase.split.include?(REL_TOKEN)
        end

        def switched_on?(value) = !value.nil? && !OFF_VALUES.include?(value.downcase)

        def label?(text) = text&.match?(LABEL_PATTERN)
      end
    end
  end
end
