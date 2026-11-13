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
      # Utility landmark names: peripheral unless chrome (see {.chrome_scope}).
      UTILITY_LANDMARK_NAMES = Set[:nav, :aside, :footer, :menu].freeze
      # Container names ignored as article roots.
      IGNORED_CONTAINER_NAMES = Set[:nav, :footer, :header, :dialog, :svg, :script, :style].freeze
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
      PAGE_CHROME = PAGE_CHROME_NAMES.to_set(&:to_s).freeze
      # +noscript+ too: the SST keeps one only for its file links (enclosures), never as content anchors.
      ALWAYS_CHROME = ((IGNORED_CONTAINER_NAMES.to_set(&:to_s) - PAGE_CHROME - Set['nav']) | Set['noscript']).freeze
      UTILITY_LANDMARK = UTILITY_LANDMARK_NAMES.to_set(&:to_s).freeze
      SECTIONING = SECTIONING_NAMES.to_set(&:to_s).freeze
      # ARIA roles whose subtree is chrome anywhere (+search+ is not: it may wrap the result list).
      CHROME_ROLES = Set['navigation', 'menu', 'menubar', 'dialog', 'alertdialog'].freeze
      # ARIA landmark roles that, like header/footer, are chrome only at page level.
      PAGE_CHROME_ROLES = Set['banner', 'contentinfo'].freeze
      # Utility landmark roles: the chrome roles plus +complementary+ (the aside role).
      UTILITY_ROLES = (CHROME_ROLES | Set['complementary']).freeze
      # A nav or list labelled (aria-label) or classed as pagination is chrome in any scope.
      PAGER_NAMES = Set['nav', 'ul', 'ol'].freeze
      # Pagination nouns ("Results pagination", "paginación"), never +paginated+.
      PAGER_LABEL = /\bpagina(?:tion|tie|ción|cion|zione|cja|ção|cao)(?!\p{L})|\bpaginering\b|\bpaginierung\b|
                     \bpager\b|\bpaging\b|\bpage\snavigation\b/ix
      # nav: a class-token part (+pagination+, +gsc-pagination+, +pager__list+), not +paginated-list+.
      PAGER_CLASS = /(?:\A|\s|[-_])(?:pagination|pager|paging)(?:\z|\s|[-_])/i
      # ul/ol: only a whole class token (+infinite-pager+ or +js-pagination-container+ is a feed list).
      PAGER_TOKENS = Set['pagination', 'pager', 'paging'].freeze
      PAGER_RELS = Set['next', 'prev', 'previous'].freeze
      # A nav linking rel=next/prev is a pager.
      PAGER_LINK_XPATH = PAGER_RELS.map { "contains(concat(' ', normalize-space(@rel), ' '), ' #{_1} ')" }
                                   .join(' or ').then { ".//a[#{_1}]" }.freeze
      # Page-navigation link shapes: a page number, an arrow, prev/next wording, or a page query/path.
      PAGE_LINK_TEXT = /\A(?:\d{1,4}|[«‹›»←→<>]+|\W*(?:prev(?:ious)?|next|older|newer|first|last)\b.*)\z/im
      PAGE_LINK_HREF = %r{[?&](?:page|paged|pg|p)=\d+|/page/\d+}i
      private_constant :PAGE_CHROME, :ALWAYS_CHROME, :UTILITY_LANDMARK, :SECTIONING, :CHROME_ROLES,
                       :PAGE_CHROME_ROLES, :UTILITY_ROLES, :PAGER_NAMES, :PAGER_LABEL, :PAGER_CLASS,
                       :PAGER_TOKENS, :PAGER_RELS, :PAGER_LINK_XPATH, :PAGE_LINK_TEXT, :PAGE_LINK_HREF

      ##
      # The single chrome-scope rule, folded down the tree by both the SST normalizer
      # and the Nokogiri ancestor walk. +:chrome+ sticks: dialog, noscript and the ARIA navigation,
      # menu and dialog roles are chrome; header/footer/nav and the banner/contentinfo roles
      # are chrome only at +:page+ level; a pager (a nav labelled or classed as pagination or
      # linking rel=next/prev, or a list labelled or whole-token classed as pagination whose
      # links mostly look like page navigation) is chrome in any scope. Otherwise a
      # utility landmark ({.utility_landmark?}) opens a sticky +:peripheral+ scope, and
      # article/section/main (or role=main) open +:sectioned+, so card headers and in-content
      # nav lists stay out of chrome.
      #
      # @param element [Nokogiri::XML::Element] element being entered
      # @param scope [Symbol] parent scope: +:page+, +:sectioned+, +:peripheral+, or +:chrome+
      # @return [Symbol] scope the element's subtree inherits
      def self.chrome_scope(element, scope)
        tag = Html::Probe.tag(element)
        roles = role_tokens(element['role'])
        return :chrome if scope == :chrome || chrome?(element, tag, roles, scope)
        return :peripheral if scope == :peripheral || utility?(tag, roles)

        SECTIONING.include?(tag) || roles.include?('main') ? :sectioned : scope
      end

      ##
      # Utility landmark: nav/aside/footer/menu, or a navigation, menu, dialog or
      # complementary role. Peripheral content when not chrome; never an article card.
      #
      # @param tag [String] folded tag name
      # @param role [String, nil] raw +role+ attribute
      # @return [Boolean]
      def self.utility_landmark?(tag, role) = utility?(tag, role_tokens(role))

      ##
      # Chrome only at page level: header/footer, or the banner/contentinfo role.
      #
      # @param tag [String] folded tag name
      # @param role [String, nil] raw +role+ attribute
      # @return [Boolean]
      def self.page_level_chrome?(tag, role) = page_level?(tag, role_tokens(role))

      def self.role_tokens(role) = role ? role.downcase.split : []

      def self.utility?(tag, roles) = UTILITY_LANDMARK.include?(tag) || roles.any? { UTILITY_ROLES.include?(_1) }

      def self.page_level?(tag, roles) = PAGE_CHROME.include?(tag) || roles.any? { PAGE_CHROME_ROLES.include?(_1) }

      def self.chrome?(element, tag, roles, scope)
        return true if ALWAYS_CHROME.include?(tag) || roles.any? { CHROME_ROLES.include?(_1) }

        (scope == :page && (tag == 'nav' || page_level?(tag, roles))) || pager?(element, tag)
      end

      def self.pager?(element, tag)
        return false unless PAGER_NAMES.include?(tag)
        return list_pager?(element) unless tag == 'nav'
        return true if element['aria-label'].to_s.match?(PAGER_LABEL) || element['class'].to_s.match?(PAGER_CLASS)

        !element.at_xpath(PAGER_LINK_XPATH).nil?
      end

      # A list is a pager only when labelled or whole-token classed as one and at least
      # half of its links look like page navigation.
      def self.list_pager?(element)
        named = element['aria-label'].to_s.match?(PAGER_LABEL) ||
                element['class'].to_s.downcase.split.any? { PAGER_TOKENS.include?(_1) }
        links = named ? element.css('a') : []
        !links.empty? && links.count { page_link?(_1) } * 2 >= links.size
      end

      def self.page_link?(link)
        link['rel'].to_s.downcase.split.any? { PAGER_RELS.include?(_1) } ||
          link['href'].to_s.match?(PAGE_LINK_HREF) || link.text.strip.match?(PAGE_LINK_TEXT)
      end
      private_class_method :role_tokens, :utility?, :page_level?, :chrome?, :pager?, :list_pager?, :page_link?
    end
  end
end
