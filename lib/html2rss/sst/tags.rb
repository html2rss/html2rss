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
      # nav: a class-token part (+pagination+, +gsc-pagination+, +pager__list+), not +paginated-list+.
      PAGER_CLASS = /(?:\A|\s|[-_])(?:pagination|pager|paging)(?:\z|\s|[-_])/i
      # ul/ol: only a whole class token (+infinite-pager+ or +js-pagination-container+ is a feed list).
      PAGER_TOKENS = Set['pagination', 'pager', 'paging'].freeze
      PAGER_RELS = Set['next', 'prev', 'previous'].freeze
      # A nav linking rel=next/prev is a pager.
      PAGER_LINK_XPATH = PAGER_RELS.map { "contains(concat(' ', normalize-space(@rel), ' '), ' #{_1} ')" }
                                   .join(' or ').then { ".//a[#{_1}]" }.freeze
      PAGE_LINK_HREF = %r{[?&](?:page|paged|pg|p)=\d+|/page/\d+}i
      private_constant :PAGE_CHROME, :ALWAYS_CHROME, :UTILITY_LANDMARK, :SECTIONING, :CHROME_ROLES,
                       :PAGE_CHROME_ROLES, :UTILITY_ROLES, :PAGER_NAMES, :PAGER_CLASS,
                       :PAGER_TOKENS, :PAGER_RELS, :PAGER_LINK_XPATH, :PAGE_LINK_HREF

      ##
      # How the pager concepts ({Vocabulary::PAGE_PATTERNS}: +pager_label+, +page_link+, +page_link_label+) are
      # read: one precompiled set of matchers per page scope, built at load. The shared terms are every language of
      # {Vocabulary::ALL}; a {Vocabulary::PAGE_ONLY} language adds its own, read as whole labels only (a Han term
      # has no word boundary). Scopes with the same own terms (every shared language and +:all+ have none) share
      # one entry, so a scope without own terms reads exactly the shared terms.
      module PagerReadings
        # The matchers of one scope: pager nouns, page-link wording and whole page-link labels.
        Readings = Data.define(:pager_label, :page_link_text, :page_link_label)

        # Whole text of one own term, wrapped in punctuation only.
        WHOLE = ->(alternation) { /\A[^\p{L}\p{N}]*(?:#{alternation})[^\p{L}\p{N}]*\z/i }

        class << self
          ##
          # @param own [Hash{Symbol => String}] a scope's own alternatives per pager concept
          # @return [Readings] +pager_label+ (pagination nouns such as "Results pagination" or "paginación", never
          #   +paginated+), +page_link_text+ (a page number, an arrow, prev/next wording) and +page_link_label+ (a
          #   whole previous/next/older/newer label such as "Suivant »" or "次へ", never one that goes on)
          def build(own)
            Readings.new(
              pager_label: own_pager_label(own.fetch(:pager_label)),
              page_link_text: /\A(?:\d{1,4}|[«‹›»←→<>]+|\W*(?:#{Vocabulary.alternation(:page_link)})\b.*)\z/im,
              page_link_label: WHOLE.call([Vocabulary.alternation(:page_link_label), own.fetch(:page_link),
                                           own.fetch(:page_link_label)].reject(&:empty?).join('|'))
            ).freeze
          end

          private

          def own_pager_label(own)
            shared = /\b(?:#{Vocabulary.alternation(:pager_label)})/ix
            own.empty? ? shared : Regexp.union(shared, WHOLE.call(own))
          end
        end

        # Per scope code; scopes with the same own terms share one entry.
        BY_SCOPE = begin
          built = {}
          Vocabulary::SCOPES.transform_values do |scope|
            own = %i[pager_label page_link page_link_label].to_h { [_1, scope.own_alternation(_1)] }
            built[own] ||= build(own)
          end.freeze
        end
        private_constant :WHOLE
      end

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
      # @param vocabulary [Vocabulary::Scope] the page language's scope, read for the pager words
      # @return [Symbol] scope the element's subtree inherits
      def self.chrome_scope(element, scope, vocabulary)
        tag = Html::Probe.tag(element)
        roles = role_tokens(element['role'])
        return :chrome if scope == :chrome || chrome?(element, tag, roles, scope, vocabulary)
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

      def self.chrome?(element, tag, roles, scope, vocabulary)
        return true if ALWAYS_CHROME.include?(tag) || roles.any? { CHROME_ROLES.include?(_1) }

        (scope == :page && (tag == 'nav' || page_level?(tag, roles))) || pager?(element, tag, vocabulary)
      end

      def self.pager?(element, tag, vocabulary)
        return false unless PAGER_NAMES.include?(tag)

        readings = PagerReadings::BY_SCOPE.fetch(vocabulary.code)
        return list_pager?(element, readings) unless tag == 'nav'
        if element['aria-label'].to_s.match?(readings.pager_label) || element['class'].to_s.match?(PAGER_CLASS)
          return true
        end

        !element.at_xpath(PAGER_LINK_XPATH).nil?
      end

      # A list is a pager only when labelled or whole-token classed as one and at least
      # half of its links look like page navigation.
      def self.list_pager?(element, readings)
        links = named_pager?(element, readings) ? element.css('a') : []
        !links.empty? && links.count { page_link?(_1, readings) } * 2 >= links.size
      end

      def self.named_pager?(element, readings)
        element['aria-label'].to_s.match?(readings.pager_label) ||
          element['class'].to_s.downcase.split.any? { PAGER_TOKENS.include?(_1) }
      end

      def self.page_link?(link, readings)
        text = link.text.strip
        link['rel'].to_s.downcase.split.any? { PAGER_RELS.include?(_1) } ||
          link['href'].to_s.match?(PAGE_LINK_HREF) || text.match?(readings.page_link_text) ||
          text.match?(readings.page_link_label)
      end
      private_class_method :role_tokens, :utility?, :page_level?, :chrome?, :pager?, :list_pager?, :named_pager?,
                           :page_link?
    end
  end
end
