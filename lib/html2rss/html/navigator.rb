# frozen_string_literal: true

module Html2rss
  module Html
    ##
    # Navigator owns DOM chrome recognition and node traversal helpers.
    class Navigator
      # String forms of {SST::Tags} (the vocabulary owner); no delta today.
      # Heading tags used to prioritize title extraction and container assessment.
      HEADING_TAGS = SST::Tags::HEADING_NAMES.to_set(&:to_s).freeze

      # Element tags that indicate ignored DOM chrome when found in a container path.
      IGNORED_CONTAINER_TAGS = SST::Tags::IGNORED_CONTAINER_NAMES.to_set(&:to_s).freeze

      # Immediate parent walk stops here — not a usable article card. Utility landmarks
      # (tags and roles, {SST::Tags.utility_landmark?}) stop too, and page-level header/footer
      # (or banner/contentinfo roles), via {usable_card_parent?}.
      CARD_WALK_STOP_TAGS = (IGNORED_CONTAINER_TAGS | Set['html', 'body']).freeze

      # Inner tags that mean a wrapping <a> is a card, not a span-styled list link.
      WRAPPING_ANCHOR_CHILD_TAGS = (HEADING_TAGS + %w[p]).freeze

      # Anchor selector used to identify the canonical article link element.
      MAIN_ANCHOR_SELECTOR = begin
        buf = +'a[href]:not([href=""])'
        SST::Tags::SKIP_HREF_PREFIXES.each do |prefix|
          buf << %[:not([href^="#{prefix}"])]
        end
        buf.freeze
      end

      class << self
        ##
        # Immediate parent is a usable article card (not html/body/landmark chrome).
        # A header/footer inside article/section/aside/main belongs to its card.
        #
        # @param node [Nokogiri::XML::Node, SST::Node, nil]
        # @param vocabulary [Vocabulary::Scope] the page language's scope, read for the pager words of a Nokogiri
        #   node's ancestors (an SST node's scope is already in its index)
        # @return [Boolean]
        def usable_card_parent?(node, vocabulary:)
          return false unless node
          return false if node.is_a?(Nokogiri::XML::Document)

          tag = Probe.tag(node)
          role = node.is_a?(SST::Node) ? node.attrs.raw['role'] : node['role']
          return !page_chrome?(node, vocabulary) if SST::Tags.page_level_chrome?(tag, role)

          !CARD_WALK_STOP_TAGS.include?(tag) && !SST::Tags.utility_landmark?(tag, role)
        end

        private

        # Whether a header/footer is page-level chrome. SST nodes defer to the
        # Normalizer's chrome index (unindexed nodes stay chrome); Nokogiri nodes
        # check for a sectioning ancestor.
        #
        # @param node [Nokogiri::XML::Node, SST::Node]
        # @param vocabulary [Vocabulary::Scope]
        # @return [Boolean]
        def page_chrome?(node, vocabulary)
          if node.is_a?(SST::Node)
            index = SST::Index.for_node(node)
            return index.nil? || index.ignored_chrome?(node)
          end

          nokogiri_chrome_scope(node, vocabulary) == :chrome
        end

        # Folds {SST::Tags.chrome_scope} over a Nokogiri node's ancestors, root first.
        #
        # @param node [Nokogiri::XML::Node]
        # @param vocabulary [Vocabulary::Scope]
        # @return [Symbol] +:page+, +:sectioned+, or +:chrome+
        def nokogiri_chrome_scope(node, vocabulary)
          (node.ancestors.reverse << node).reduce(:page) do |scope, el|
            el.element? ? SST::Tags.chrome_scope(el, scope, vocabulary) : scope
          end
        end
      end
    end
  end
end
