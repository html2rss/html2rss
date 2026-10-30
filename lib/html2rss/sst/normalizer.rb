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

      # Tags stripped entirely from the SST.
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
          style |
          datetime |
          itemprop |
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

      # String form of Tags::IGNORED_CONTAINER_NAMES for chrome checks without to_sym.
      IGNORED_CONTAINER_TAGS = Tags::IGNORED_CONTAINER_NAMES.to_set(&:to_s).freeze

      class << self
        ##
        # @param input [String, Nokogiri::HTML::Document, Nokogiri::XML::Node]
        #   HTML string or already-parsed node (String is parsed once here)
        # @return [Document, nil] +nil+ when no SST nodes survive normalization
        # @raise [InvalidOption] when input is nil or unsupported
        def call(input)
          raise InvalidOption, 'input is required' if input.nil?

          new(coerce(input)).call
        end

        private

        # @param input [String, Nokogiri::XML::Node]
        # @return [Nokogiri::XML::Node]
        def coerce(input)
          case input
          when String then Nokogiri::HTML(input)
          when Nokogiri::XML::Node then input
          else
            raise InvalidOption, "expected String or Nokogiri::XML::Node, got #{input.class}"
          end
        end
      end

      # @param parsed_body [Nokogiri::HTML::Document, Nokogiri::XML::Node]
      def initialize(parsed_body)
        @parsed_body = parsed_body
        @node_count = 0
        @degraded = false
        @parents = {}.compare_by_identity
        @depths = {}.compare_by_identity
        @ignored_chrome = {}.compare_by_identity
      end

      ##
      # @return [Document, nil] +nil+ when no SST nodes survive normalization
      def call
        root_nk = resolve_root_nk
        root = normalize_element(root_nk, depth: 0, path: '', chrome: false)
        return unless root

        index = Index.new(root:, parents: @parents, depths: @depths, ignored_chrome: @ignored_chrome)
        Document.build(root:, index:, degraded: @degraded, node_count: @node_count)
      end

      private

      # @return [Nokogiri::XML::Node]
      # rubocop:disable-next Metrics/MethodLength -- explicit root discovery fallback chain
      def resolve_root_nk
        parsed = @parsed_body

        html = parsed.at_css('html')
        return html if html

        body = parsed.at_css('body')
        if body
          Html2rss::Log.warn({
            event_name: 'sst.normalizer.root_fallback',
            reason: 'body',
            message: 'sst.normalizer root fallback: body'
          }.to_json)
          return body
        end

        first = parsed.element_children.find { |child| element_root?(child) }
        if first
          Html2rss::Log.warn({
            event_name: 'sst.normalizer.root_fallback',
            reason: 'first_element_child',
            message: 'sst.normalizer root fallback: first element child'
          }.to_json)
          return first
        end

        Html2rss::Log.warn({
          event_name: 'sst.normalizer.root_fallback',
          reason: 'self',
          message: 'sst.normalizer root fallback: self'
        }.to_json)
        parsed
      end

      def element_root?(node)
        node.element? && !STRIPPED_TAGS.include?(Html2rss::Html::Probe.tag(node))
      end

      # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def normalize_element(nk_node, depth:, path:, chrome:)
        return unless nk_node.element?

        tag = Html::Probe.tag(nk_node)
        return if STRIPPED_TAGS.include?(tag)

        if @node_count >= MAX_NODES && !@degraded
          @degraded = true
          Log.warn({
            event_name: 'sst.normalizer.max_nodes',
            max_nodes: MAX_NODES,
            message: "sst.normalizer MAX_NODES=#{MAX_NODES} breached; degrading to semantic-tag-only"
          }.to_json)
        end

        return if @degraded && !SEMANTIC_DEGRADE_TAGS.include?(tag)

        @node_count += 1
        tag_path = "#{path}/#{tag}"
        attrs = extract_attrs(nk_node)
        chrome_here = chrome || IGNORED_CONTAINER_TAGS.include?(tag)

        children, lead, tails = normalize_children(nk_node, depth:, path: tag_path, chrome: chrome_here)

        node = Node.build(name: tag, attrs:, own_text: [lead, *tails].join, children:, tag_path:, tails:)
        @depths[node] = depth
        @ignored_chrome[node] = chrome_here
        children.each { |child| @parents[child] = node }

        node
      end

      def extract_attrs(nk_node) # rubocop:disable Metrics/MethodLength
        Attrs.build(
          href: nk_node['href'],
          src: nk_node['src'],
          id: nk_node['id'],
          class_names: nk_node['class'].to_s.split(/\s+/).reject(&:empty?),
          datetime: nk_node['datetime'],
          itemprop: nk_node['itemprop'],
          style: nk_node['style'],
          srcset: nk_node['srcset'],
          type: nk_node['type'],
          raw: raw_attrs(nk_node)
        )
      end

      def raw_attrs(nk_node)
        nk_node.attribute_nodes.each_with_object({}) do |attr, raw|
          name = attr.name.to_s
          next if TYPED_ATTR_NAMES.include?(name)
          next unless name.match?(RAW_ATTR_KEEP)

          raw[name] = attr.value.to_s
        end
      end

      # Walks child nodes once, keeping direct text in the slot of the preceding kept child
      # (slot 0 is the lead text) so text order survives the element-only tree.
      def normalize_children(nk_node, depth:, path:, chrome:)
        children = []
        slots = [+'']
        nk_node.children.each do |child|
          next slots.last << child.text if child.text?

          node = normalize_element(child, depth: depth + 1, path:, chrome:)
          (children << node) && (slots << +'') if node
        end
        [children, slots.first, slots.drop(1)]
      end
    end
  end
end
