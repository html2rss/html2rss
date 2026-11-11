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
          attribute_marker?(node.attrs) || (node.name != :a && label?(node.own_text))
        end

        private

        def attribute_marker?(attrs)
          raw = attrs.raw
          sponsored_rel?(raw['rel']) ||
            ATTRIBUTE_NAMES.any? { switched_on?(raw[_1]) } ||
            attrs.class_names.any? { CLASS_NAMES.include?(_1) || _1.match?(AD_LABEL_CLASS) } ||
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
