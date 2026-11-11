# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Shared tag-name and href constants for SST nodes.
    module Tags
      # Heading element names.
      HEADING_NAMES = Set[:h1, :h2, :h3, :h4, :h5, :h6].freeze
      # Block-level names that contribute structural newlines in text.
      BLOCK_NAMES = Set[:p, :div, :li, :ul, :ol, :h1, :h2, :h3, :h4, :h5, :h6, :tr, :br].freeze
      # Names skipped when collecting visible text.
      INVISIBLE_NAMES = Set[:svg, :script, :noscript, :style, :template].freeze
      # Landmark names treated as utility chrome.
      UTILITY_LANDMARK_NAMES = Set[:nav, :aside, :footer, :menu].freeze
      # Container names ignored as article roots.
      IGNORED_CONTAINER_NAMES = Set[:nav, :footer, :header, :svg, :script, :style].freeze
      # Ignored containers that are chrome only at page level (ARIA banner/contentinfo scoping).
      PAGE_CHROME_NAMES = Set[:header, :footer].freeze
      # Ancestors that scope a header/footer to their own section instead of the page.
      SECTIONING_NAMES = Set[:article, :section, :aside, :main].freeze
      # Names excluded from class/structure clustering.
      CLUSTER_EXCLUDED_NAMES = Set[:html, :body, :nav, :footer, :header, :svg, :script, :style].freeze
      # Href prefixes that never count as content destinations.
      SKIP_HREF_PREFIXES = ['#', 'javascript:', 'mailto:', 'tel:', 'file://', 'sms:', 'data:'].freeze
      # Layout-ish names used when resolving nested wrapper groups.
      LAYOUT_NAMES = Set[:div, :section, :article, :li, :ul, :ol].freeze

      ALWAYS_CHROME = (IGNORED_CONTAINER_NAMES - PAGE_CHROME_NAMES).to_set(&:to_s).freeze
      PAGE_CHROME = PAGE_CHROME_NAMES.to_set(&:to_s).freeze
      SECTIONING = SECTIONING_NAMES.to_set(&:to_s).freeze
      private_constant :ALWAYS_CHROME, :PAGE_CHROME, :SECTIONING

      ##
      # The single chrome-scope rule, folded down the tree by both the SST normalizer
      # and the Nokogiri ancestor walk: +:chrome+ sticks; header/footer are chrome only
      # at +:page+ level, so card headers inside article/section/aside/main stay content.
      #
      # @param tag [String] folded tag name
      # @param scope [Symbol] parent scope: +:page+, +:sectioned+, or +:chrome+
      # @return [Symbol] scope the element's subtree inherits
      def self.chrome_scope(tag, scope)
        return :chrome if scope == :chrome || ALWAYS_CHROME.include?(tag)
        return :chrome if scope == :page && PAGE_CHROME.include?(tag)

        SECTIONING.include?(tag) ? :sectioned : scope
      end
    end
  end
end
