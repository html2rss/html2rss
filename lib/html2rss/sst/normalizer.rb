# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  module SST
    ##
    # Sole Nokogiri consumer on the heuristic auto-source path. Builds an
    # immutable SST::Document with parent/depth/chrome indices.
    class Normalizer # rubocop:disable Metrics/ClassLength
      # Hard ceiling for SST node allocations; beyond this we degrade.
      MAX_NODES = 5_000

      # Tags stripped entirely from the SST; a +noscript+ keeps only its file links, or all its content for
      # items (see {#kept_children}).
      STRIPPED_TAGS = Set['script', 'style', 'noscript', 'iframe', 'svg', 'template'].freeze

      # Kept when MAX_NODES forces semantic-tag-only degrade.
      SEMANTIC_DEGRADE_TAGS = Set['html', 'body', 'article', 'section', 'li', 'tr', 'div', 'a',
                                  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'time', 'img', 'p',
                                  'ul', 'ol', 'main'].freeze

      # Attribute names preserved in Attrs#raw for extraction.
      RAW_ATTR_KEEP = /
        \A(
          data- |
          aria- |
          class |
          id |
          href |
          src |
          srcset |
          poster\z |
          title\z |
          style |
          datetime |
          itemprop |
          rel\z |
          hidden\z |
          role |
          type |
          category |
          categories |
          tag |
          tags |
          topic |
          topics |
          section |
          sections |
          label |
          labels |
          theme |
          themes |
          subject |
          subjects
        )
      /xi

      # Typed Attrs fields excluded from the leftover raw hash.
      TYPED_ATTR_NAMES = Set['href', 'src', 'id', 'class', 'datetime', 'itemprop', 'style', 'srcset', 'type'].freeze

      # Shared, frozen empty text slot.
      EMPTY_TEXT = ''

      class << self
        ##
        # @param input [String, Nokogiri::HTML::Document, Nokogiri::XML::Node]
        #   HTML string or already-parsed node (String is parsed once here)
        # @param vocabulary [Vocabulary::Scope] the page language's scope, read for the pager words that make a
        #   list or nav chrome
        # @param items [Boolean] normalize for items a selector config picked in the parsed page ({Selectors}),
        #   not for the heuristic: record which parsed node each SST node came from ({Index#node_for}), never
        #   degrade at {MAX_NODES}, keep the content of a +noscript+, and log a fallback root at debug (the page may
        #   be a parsed fragment). Off allocates no node map.
        # @param within [Symbol, nil] +input+ is the root element of a region of the page, not the page: the
        #   chrome scope (+:page+, +:sectioned+, +:peripheral+, +:chrome+) its parent gives it
        # @return [Document, nil] +nil+ when no SST nodes survive normalization
        # @raise [InvalidError] when input is nil or unsupported
        def call(input, vocabulary:, items: false, within: nil)
          raise InvalidError, 'input is required' if input.nil?

          new(coerce(input), vocabulary, items:, within:).call
        end

        ##
        # @param tag [String] folded tag name of a parsed element
        # @param items [Boolean] see {.call}
        # @return [Boolean] whether the element becomes an SST node (a +noscript+ only for items)
        def kept_tag?(tag, items:) = !STRIPPED_TAGS.include?(tag) || (items && tag == 'noscript')

        private

        # @param input [String, Nokogiri::XML::Node]
        # @return [Nokogiri::XML::Node]
        def coerce(input)
          case input
          when String then Nokogiri::HTML(input)
          when Nokogiri::XML::Node then input
          else
            raise InvalidError, "expected String or Nokogiri::XML::Node, got #{input.class}"
          end
        end
      end

      # @param parsed_body [Nokogiri::HTML::Document, Nokogiri::XML::Node]
      # @param vocabulary [Vocabulary::Scope]
      # @param items [Boolean] see {.call}
      # @param within [Symbol, nil] see {.call}
      def initialize(parsed_body, vocabulary, items:, within:) # rubocop:disable Metrics/MethodLength -- per-run state
        @parsed_body = parsed_body
        @vocabulary = vocabulary
        @items = items
        @within = within
        @sources = ({}.compare_by_identity if items)
        @node_count = 0
        @degraded = false
        @parents = {}.compare_by_identity
        @depths = {}.compare_by_identity
        @scopes = {}.compare_by_identity
        @class_tokens = {}
        @tag_paths = Hash.new { |paths, path| paths[path] = {} }
      end

      ##
      # @return [Document, nil] +nil+ when no SST nodes survive normalization
      def call
        root_nk = @within ? @parsed_body : resolve_root_nk
        root = normalize_element(root_nk, depth: 0, path: '', scope: @within || :page)
        return unless root

        index = Index.new(root:, parents: @parents, depths: @depths, scopes: @scopes, sources: @sources)
        Document.build(root:, index:, degraded: @degraded, node_count: @node_count)
      end

      private

      # @return [Nokogiri::XML::Node]
      def resolve_root_nk
        parsed = @parsed_body

        html = parsed.at_css('html')
        return html if html

        body = parsed.at_css('body')
        return log_root_fallback('body', body) if body

        first = parsed.element_children.find { |child| element_root?(child) }
        return log_root_fallback('first_element_child', first) if first

        log_root_fallback('self', parsed)
      end

      # @return [Nokogiri::XML::Node] +root+, after logging the fallback that chose it
      def log_root_fallback(reason, root)
        message = "sst.normalizer root fallback: #{reason.tr('_', ' ')}"
        payload = { event_name: 'sst.normalizer.root_fallback', reason:, message: }.to_json
        @items ? Html2rss::Log.debug(payload) : Html2rss::Log.warn(payload)
        root
      end

      def element_root?(node) = self.class.kept_tag?(Html2rss::Html::Probe.tag(node), items: @items)

      # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
      def normalize_element(nk_node, depth:, path:, scope:)
        return unless nk_node.element?

        tag = Html::Probe.tag(nk_node)
        return unless (kept = kept_children(nk_node, tag))

        degrade_when_full
        return if @degraded && !SEMANTIC_DEGRADE_TAGS.include?(tag)

        @node_count += 1
        tag_path = (@tag_paths[path][tag] ||= "#{path}/#{tag}")
        attrs = extract_attrs(nk_node)
        scope_here = Tags.chrome_scope(nk_node, scope, @vocabulary, tag)

        tails = [EMPTY_TEXT]
        children = normalize_children(kept, tails, depth:, path: tag_path, scope: scope_here)
        own_text = join_text(tails.shift, tails)

        node = Node.build(name: tag, attrs:, own_text:, children:, tag_path:, tails:)
        index_node(node, nk_node, depth, scope_here)
      end

      # Records the index entries of +node+ and its children, and returns +node+.
      def index_node(node, nk_node, depth, scope)
        @depths[node] = depth
        @sources[nk_node] = node if @sources
        @scopes[node] = scope
        node.children.each { |child| @parents[child] = node }

        node
      end

      def degrade_when_full
        return unless !@items && @node_count >= MAX_NODES && !@degraded

        @degraded = true
        Log.warn({
          event_name: 'sst.normalizer.max_nodes',
          max_nodes: MAX_NODES,
          message: "sst.normalizer MAX_NODES=#{MAX_NODES} breached; degrading to semantic-tag-only"
        }.to_json)
      end

      # The node whose children to normalize, or nil for a stripped tag. A +noscript+ is kept only for the
      # file links inside it ({Html::ArticleRules::Enclosure.file_link?}), as its only children, so a
      # card's no-script download link still names its enclosure; its text stays invisible
      # ({Tags::INVISIBLE_NAMES}) and a +noscript+ without one is stripped; its file links come back as an
      # Array standing in for its children. The root of a region is a +template+ the config selected as an
      # item: its content is the item, so it is kept.
      #
      # @return [Nokogiri::XML::Node, Array<Nokogiri::XML::Node>, nil]
      def kept_children(nk_node, tag)
        return nk_node if self.class.kept_tag?(tag, items: @items) || region_template?(nk_node, tag)
        return unless tag == 'noscript'

        links = nk_node.xpath('.//a[@href]').select { Html::ArticleRules::Enclosure.file_link?(_1['href']) }
        links unless links.empty?
      end

      def region_template?(nk_node, tag) = @within && tag == 'template' && nk_node.equal?(@parsed_body)

      def extract_attrs(nk_node) # rubocop:disable Metrics/MethodLength
        attr_nodes = nk_node.attribute_nodes
        return Attrs.empty if attr_nodes.empty?

        Attrs.build(
          href: nk_node['href'],
          src: nk_node['src'],
          id: nk_node['id'],
          class_names: class_tokens(nk_node['class']),
          datetime: nk_node['datetime'],
          itemprop: nk_node['itemprop'],
          style: nk_node['style'],
          srcset: nk_node['srcset'],
          type: nk_node['type'],
          raw: raw_attrs(attr_nodes)
        )
      end

      # Repeated card classes share one token list, frozen by {Attrs.build}. The cache lives and dies with this
      # normalizer and holds one entry per distinct class attribute of its kept nodes.
      #
      # @return [Array<String>, nil] tokens, +nil+ without a class attribute
      def class_tokens(class_attr)
        return unless class_attr

        @class_tokens[class_attr] ||= class_attr.split
      end

      # @return [Hash{String => String}, nil] kept attributes, +nil+ when none
      def raw_attrs(attr_nodes)
        raw = nil
        attr_nodes.each do |attr|
          name = attr.name
          next if TYPED_ATTR_NAMES.include?(name)

          (raw ||= {})[name] = attr.value if name.match?(RAW_ATTR_KEEP)
        end
        raw
      end

      # Walks child nodes once, keeping direct text in the slot of the preceding kept child
      # (slot 0 is the lead text) so text order survives the element-only tree. The caller owns +slots+.
      def normalize_children(kept, slots, depth:, path:, scope:)
        children = []
        each_child(kept) do |child|
          next append_text(slots, child.text) if child.text?

          node = normalize_element(child, depth: depth + 1, path:, scope:)
          (children << node) && (slots << EMPTY_TEXT) if node
        end
        children
      end

      # Sibling walk: +children+ would build a NodeSet per element.
      def each_child(kept)
        return kept.each { yield _1 } if kept.is_a?(Array)

        child = kept.child
        while child
          yield child
          child = child.next_sibling
        end
      end

      # Direct text lands in the last slot; an empty slot takes the fresh string, so no slot is pre-allocated.
      def append_text(slots, text)
        last = slots.last
        last.empty? ? (slots[-1] = text) : last << text
      end

      # The node's own text: the lead and tails in document order. Appends to +lead+, which the caller
      # no longer reads, unless it is the shared empty slot.
      def join_text(lead, tails)
        return lead if tails.all?(&:empty?)

        tails.each_with_object(+lead) { |tail, text| text << tail }
      end
    end
  end
end
