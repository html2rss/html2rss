# frozen_string_literal: true

module Html2rss
  ##
  # Ranks Capture-derived selector evidence into deterministic best-first buckets.
  #
  # Owns collection into buckets, deduplication, ranking, and empty-bucket semantics.
  # Does not emit the default +a[href]+ fallback — that remains Capture's YAML path only.
  class SelectorCandidates # rubocop:disable Metrics/ClassLength -- ranking + field CSS stay co-located
    # Empty candidate buckets (no discovered evidence).
    EMPTY = {
      items: [].freeze, title: [].freeze, link: [].freeze, published: [].freeze, candidates_by_item: [].freeze
    }.freeze

    # How many top-ranked item candidates get their own field buckets in +:candidates_by_item+.
    BY_ITEM_LIMIT = 5

    # Ranking preference for items selector derivation kind (lower is better).
    KIND_RANK = { shared_class: 0, unique_tag: 1, path: 2 }.freeze
    private_constant :KIND_RANK

    # Ranking preference for Segmenter strategy order (lower is better).
    STRATEGY_RANK = { list: 0, cluster: 1, semantic: 2 }.freeze
    private_constant :STRATEGY_RANK

    # Minimum roots that must share a relative field selector.
    DEFAULT_MIN_MATCHES = 2
    private_constant :DEFAULT_MIN_MATCHES

    # Class token that identifies a non-heading title node. Owned by the extractor so both match the same nodes.
    TITLE_CLASS_PATTERN = Html::SstArticleExtractor::TITLE_CLASS_PATTERN
    private_constant :TITLE_CLASS_PATTERN

    class << self
      ##
      # @return [Hash{Symbol=>Array}] frozen empty buckets
      def empty = EMPTY

      ##
      # Ranks items evidence and derives title/link/published field selectors.
      #
      # @param items_evidence [Array<Hash>] each with +:selector+, +:enhance+, +:strategy+,
      #   +:kind+, +:match_count+, and +:roots+ (SST nodes under the items selector)
      # @param min_matches [Integer] minimum repeated field evidence across roots
      # @return [Hash{Symbol=>Array<Hash>}] +:items+, +:title+, +:link+, +:published+ (buckets for the
      #   top item) and +:candidates_by_item+ (per-item buckets for the top {BY_ITEM_LIMIT} items)
      def call(items_evidence:, min_matches: DEFAULT_MIN_MATCHES)
        new(items_evidence:, min_matches:).call
      end
    end

    ##
    # @param items_evidence [Array<Hash>]
    # @param min_matches [Integer]
    def initialize(items_evidence:, min_matches: DEFAULT_MIN_MATCHES)
      @items_evidence = Array(items_evidence)
      @min_matches = min_matches
    end

    ##
    # @return [Hash{Symbol=>Array<Hash>}]
    def call
      items = rank_items(@items_evidence)
      return EMPTY if items.empty?

      by_item = items.first(BY_ITEM_LIMIT).map { |item| item_buckets(item) }
      { items:, **by_item.first.slice(:title, :link, :published), candidates_by_item: by_item }
    end

    private

    def item_buckets(item)
      roots = roots_for(item, @items_evidence)
      {
        selector: item.fetch(:selector),
        title: field_bucket(roots, :title),
        link: field_bucket(roots, :link),
        published: field_bucket(roots, :published)
      }
    end

    def rank_items(evidence)
      evidence
        .sort_by { |entry| item_rank_key(entry) }
        .each_with_object([]) do |entry, ranked|
          selector = entry[:selector].to_s
          next if selector.empty? || ranked.any? { |c| c[:selector] == selector }

          ranked << item_candidate(entry)
        end
    end

    def item_candidate(entry)
      {
        selector: entry[:selector].to_s,
        enhance: entry[:enhance],
        sample: visible_sample(Array(entry[:roots]).first)
      }
    end

    def item_rank_key(entry)
      [
        KIND_RANK.fetch(entry[:kind], 99),
        STRATEGY_RANK.fetch(entry[:strategy], 99),
        -entry[:match_count].to_i,
        entry[:selector].to_s
      ]
    end

    def roots_for(top_item, evidence)
      match = evidence.find { |entry| entry[:selector].to_s == top_item[:selector] }
      Array(match&.fetch(:roots, nil))
    end

    def field_bucket(roots, field)
      usable = roots.grep(SST::Node)
      return [] if usable.size < @min_matches

      rank_field_tallies(count_field_selectors(usable, field))
    end

    def count_field_selectors(roots, field)
      roots.each_with_object({}) do |root, tallies|
        node = field_node(root, field)
        selector = relative_field_selector(root, field)
        next unless selector

        tallies[selector] ||= { count: 0, sample: visible_sample(node) }
        tallies[selector][:count] += 1
      end
    end

    def rank_field_tallies(tallies)
      tallies
        .select { |_selector, data| data[:count] >= @min_matches }
        .sort_by { |selector, data| [-data[:count], selector.length, selector] }
        .map { |selector, data| { selector:, sample: data[:sample] } }
    end

    def visible_sample(node)
      node&.visible_text.to_s.gsub(/\s+/, ' ').strip
    end

    def relative_field_selector(root, field)
      node = field_node(root, field)
      token = identifying_title_class(node) if field == :title
      relative_css(root, node, class_token: token)
    end

    def field_node(root, field)
      case field
      when :title then title_node(root)
      when :link then link_node(root)
      when :published then published_node(root)
      end
    end

    def title_node(root)
      headings = root.find_all(&:heading?)
      return best_heading(headings) if headings.any?

      root.find do |node|
        next if node.equal?(root)

        identifying_title_class(node) && !node.visible_text.to_s.strip.empty?
      end
    end

    def best_heading(headings)
      min_name = headings.map { |node| node.name.to_s }.min
      headings.select { |node| node.name.to_s == min_name }
              .max_by { |node| node.visible_text.to_s.size }
    end

    def link_node(root)
      return if root.link?

      root.find(&:link?)
    end

    def published_node(root)
      root.find do |node|
        next if node.equal?(root)

        node.name == :time || !node.attrs.datetime.to_s.empty?
      end
    end

    # First class that title_node used to accept this node, not the lexicographically smallest token.
    def identifying_title_class(node)
      return if node.nil? || node.heading?

      node.attrs.class_names.find { |name| name.match?(TITLE_CLASS_PATTERN) }
    end

    def relative_css(root, node, class_token:)
      return if node.nil? || node.equal?(root)
      return "#{node.name}.#{css_escape_ident(class_token)}" if class_token

      relative_path_css(root, node)
    end

    # CSSOM "serialize an identifier" (CSS.escape). Class tokens are untrusted HTML.
    def css_escape_ident(token)
      return '\\-' if token == '-'

      token.each_char.with_index.map { |char, index| css_escaped_char(char, index, token) }.join
    end

    def css_escaped_char(char, index, token)
      code = char.ord
      return "\uFFFD" if code.zero?
      return "\\#{code.to_s(16)} " if css_hex_escape?(code, index, token)
      return char if css_ident_literal?(code)

      "\\#{char}"
    end

    def css_hex_escape?(code, index, token)
      code.between?(1, 0x1F) || code == 0x7F ||
        (index.zero? && code.between?(0x30, 0x39)) ||
        (index == 1 && code.between?(0x30, 0x39) && token.start_with?('-'))
    end

    def css_ident_literal?(code)
      code >= 0x80 || code == 0x2D || code == 0x5F ||
        code.between?(0x30, 0x39) || code.between?(0x41, 0x5A) || code.between?(0x61, 0x7A)
    end

    def relative_path_css(root, node)
      root_parts = path_parts(root)
      node_parts = path_parts(node)
      return unless node_parts[0, root_parts.length] == root_parts

      rel = node_parts[root_parts.length..]
      return if rel.nil? || rel.empty?

      rel.join(' > ')
    end

    def path_parts(node)
      node.tag_path.to_s.split('/').reject(&:empty?)
    end
  end
end
