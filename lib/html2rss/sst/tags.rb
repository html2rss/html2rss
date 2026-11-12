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

      # header/footer/nav: chrome at page level, their parent's scope inside sectioning content.
      SCOPED_CHROME = (PAGE_CHROME_NAMES | Set[:nav]).to_set(&:to_s).freeze
      ALWAYS_CHROME = IGNORED_CONTAINER_NAMES.to_set(&:to_s).freeze - SCOPED_CHROME
      SECTIONING = SECTIONING_NAMES.to_set(&:to_s).freeze
      # ARIA roles whose subtree is chrome anywhere (+search+ is not: it may wrap the result list).
      CHROME_ROLES = Set['navigation', 'menu', 'menubar', 'dialog', 'alertdialog'].freeze
      # ARIA landmark roles that, like header/footer, are chrome only at page level.
      PAGE_CHROME_ROLES = Set['banner', 'contentinfo'].freeze
      # A nav or list labelled (aria-label) or classed as pagination is chrome in any scope.
      PAGER_NAMES = Set['nav', 'ul', 'ol'].freeze
      PAGER_LABEL = /pagin(?:at|ac|az|er|ier)|\bpager\b|\bpaging\b|\bpage navigation\b/i
      # Whole class-token part (+pagination+, +gsc-pagination+, +pager__list+), not +paginated-list+.
      PAGER_CLASS = /(?:\A|\s|[-_])(?:pagination|pager|paging)(?:\z|\s|[-_])/i
      # A nav linking rel=next/prev is a pager; lists are exempt (a feed list may end in a "more" link).
      PAGER_LINK_XPATH = %w[next prev previous].map { "contains(concat(' ', normalize-space(@rel), ' '), ' #{_1} ')" }
                                               .join(' or ').then { ".//a[#{_1}]" }.freeze
      private_constant :SCOPED_CHROME, :ALWAYS_CHROME, :SECTIONING, :CHROME_ROLES, :PAGE_CHROME_ROLES,
                       :PAGER_NAMES, :PAGER_LABEL, :PAGER_CLASS, :PAGER_LINK_XPATH

      ##
      # The single chrome-scope rule, folded down the tree by both the SST normalizer
      # and the Nokogiri ancestor walk: +:chrome+ sticks; ARIA navigation, menu and dialog
      # roles are chrome; header/footer/nav and the banner/contentinfo roles are chrome only
      # at +:page+ level, so card headers and in-content nav lists inside
      # article/section/aside/main stay content; a pager (a nav or list labelled or classed
      # as pagination, or a nav linking rel=next/prev) is chrome in any scope.
      #
      # @param element [Nokogiri::XML::Element] element being entered
      # @param scope [Symbol] parent scope: +:page+, +:sectioned+, or +:chrome+
      # @return [Symbol] scope the element's subtree inherits
      def self.chrome_scope(element, scope)
        tag = Html::Probe.tag(element)
        return :chrome if scope == :chrome || ALWAYS_CHROME.include?(tag) || chrome_role?(element['role'], scope)
        return :chrome if (scope == :page && SCOPED_CHROME.include?(tag)) || pager?(element, tag)

        SECTIONING.include?(tag) ? :sectioned : scope
      end

      def self.chrome_role?(role, scope)
        role.to_s.downcase.split.any? do |token|
          CHROME_ROLES.include?(token) || (scope == :page && PAGE_CHROME_ROLES.include?(token))
        end
      end

      def self.pager?(element, tag)
        return false unless PAGER_NAMES.include?(tag)
        return true if element['aria-label'].to_s.match?(PAGER_LABEL) || element['class'].to_s.match?(PAGER_CLASS)

        tag == 'nav' && !element.at_xpath(PAGER_LINK_XPATH).nil?
      end
      private_class_method :chrome_role?, :pager?
    end
  end
end
