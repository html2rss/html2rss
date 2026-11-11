# frozen_string_literal: true

module Html2rss
  module LinkDestination
    ##
    # Explicit sponsorship markers on SST nodes: a +rel+ containing +sponsored+, an advertorial
    # attribute or class, or an ARIA label or element text that is exactly an ad label from a
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

      module_function

      ##
      # @param node [SST::Node]
      # @return [Boolean] true when +node+ itself carries an explicit sponsorship marker
      def marker?(node)
        attrs = node.attrs
        raw = attrs.raw
        sponsored_rel?(raw['rel']) ||
          ATTRIBUTE_NAMES.any? { |name| raw.key?(name) && !OFF_VALUES.include?(raw[name].downcase) } ||
          attrs.class_names.any? { CLASS_NAMES.include?(_1) } ||
          ARIA_NAMES.any? { |name| label?(raw[name]) } ||
          (node.name != :a && label?(node.own_text))
      end

      ##
      # @param text [String, nil] element text or attribute value
      # @return [Boolean] true when +text+ is exactly one ad label
      def label?(text)
        return false if text.nil? || text.empty?

        text.match?(LABEL_PATTERN)
      end

      ##
      # @param rel [String, nil] +rel+ attribute value
      # @return [Boolean]
      def sponsored_rel?(rel)
        return false unless rel

        rel.downcase.split.include?(REL_TOKEN)
      end
    end
  end
end
