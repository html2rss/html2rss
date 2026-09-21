# frozen_string_literal: true

module Html2rss
  ##
  # Ranks Capture-derived selector evidence into deterministic best-first buckets.
  #
  # Owns collection into buckets, deduplication, ranking, and empty-bucket semantics.
  # Does not emit the default +a[href]+ fallback — that remains Capture's YAML path only.
  class SelectorCandidates # rubocop:disable Metrics/ClassLength -- ranking + field CSS stay co-located
    # Empty candidate buckets (no discovered evidence).
    EMPTY = { items: [].freeze, title: [].freeze, link: [].freeze, published: [].freeze }.freeze

    # Ranking preference for items selector derivation kind (lower is better).
    KIND_RANK = { shared_class: 0, unique_tag: 1, path: 2 }.freeze
    private_constant :KIND_RANK

    # Ranking preference for Segmenter strategy order (lower is better).
    STRATEGY_RANK = { list: 0, cluster: 1, semantic: 2 }.freeze
    private_constant :STRATEGY_RANK

    # Minimum roots that must share a relative field selector.
    DEFAULT_MIN_MATCHES = 2
    private_constant :DEFAULT_MIN_MATCHES

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
      # @return [Hash{Symbol=>Array<Hash>}] +:items+, +:title+, +:link+, +:published+
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

      roots = roots_for(items.first, @items_evidence)
      {
        items:,
        title: field_bucket(roots, :title),
        link: field_bucket(roots, :link),
        published: field_bucket(roots, :published)
      }
    end

    private

    def rank_items(evidence)
      evidence
        .sort_by { |entry| item_rank_key(entry) }
        .each_with_object([]) do |entry, ranked|
          selector = entry[:selector].to_s
          next if selector.empty? || ranked.any? { |c| c[:selector] == selector }

          ranked << { selector:, enhance: entry[:enhance] }
        end
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
      usable = roots.select { |root| root.respond_to?(:find_all) }
      return [] if usable.size < @min_matches

      rank_field_counts(count_field_selectors(usable, field))
    end

    def count_field_selectors(roots, field)
      roots.each_with_object(Hash.new(0)) do |root, counts|
        selector = relative_field_selector(root, field)
        counts[selector] += 1 if selector
      end
    end

    def rank_field_counts(counts)
      counts
        .select { |_selector, count| count >= @min_matches }
        .sort_by { |selector, count| [-count, selector.length, selector] }
        .map { |selector, _count| { selector: } }
    end

    def relative_field_selector(root, field)
      relative_css(root, field_node(root, field))
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

        node.attrs.class_names.any? { |name| name.match?(/title|font-bold|font-semibold/) } &&
          !node.visible_text.to_s.strip.empty?
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

    def relative_css(root, node)
      return if node.nil? || node.equal?(root)

      classes = node.attrs.class_names
      return "#{node.name}.#{classes.min}" unless classes.empty?

      relative_path_css(root, node)
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
