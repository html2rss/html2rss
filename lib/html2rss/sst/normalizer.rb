# frozen_string_literal: true

require 'nokogiri'

module Html2rss
  module SST
    ##
    # Sole Nokogiri consumer on the heuristic auto-source path. Builds an
    # immutable SST::Document with parent/depth/chrome indices.
    class Normalizer # rubocop:disable Metrics/ClassLength
      # Raised when no SST nodes survive normalization for the chosen root.
      class EmptyTree < ArgumentError; end

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
      TYPED_ATTR_NAMES = %w[href src id class datetime itemprop style srcset type].to_set.freeze

      # String form of Tags::IGNORED_CONTAINER_NAMES for chrome checks without to_sym.
      IGNORED_CONTAINER_TAGS = Tags::IGNORED_CONTAINER_NAMES.to_set(&:to_s).freeze

      class << self
        ##
        # @param input [String, Nokogiri::HTML::Document, Nokogiri::XML::Node]
        #   HTML string or already-parsed node (String is parsed once here)
        # @return [Document]
        # @raise [ArgumentError] when input is nil or unsupported
        def call(input)
          raise ArgumentError, 'input is required' if input.nil?

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
            raise ArgumentError, "expected String or Nokogiri::XML::Node, got #{input.class}"
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
      # @return [Document]
      def call
        root_nk = resolve_root_nk
        root = normalize_element(root_nk, parent: nil, depth: 0, path: '', chrome: false)
        raise EmptyTree, 'SST Normalizer produced an empty tree' unless root

        index = Index.new(root:, parents: @parents, depths: @depths, ignored_chrome: @ignored_chrome)
        Document.build(root:, index:, degraded: @degraded, node_count: @node_count)
      end

      private

      # @return [Nokogiri::XML::Node]
      # rubocop:disable-next Metrics/MethodLength -- explicit root discovery fallback chain
      def resolve_root_nk
        parsed = @parsed_body

        if parsed.respond_to?(:at_css)
          html = parsed.at_css('html')
          return html if html

          body = parsed.at_css('body')
          if body
            Html2rss::Log.warn('sst.normalizer root fallback: body')
            return body
          end
        end

        if parsed.respond_to?(:element_children)
          first = parsed.element_children.find { |child| element_root?(child) }
          if first
            Html2rss::Log.warn('sst.normalizer root fallback: first element child')
            return first
          end
        end

        Html2rss::Log.warn('sst.normalizer root fallback: self')
        parsed
      end

      def element_root?(node)
        node.element? && !STRIPPED_TAGS.include?(Html2rss::Html::Probe.tag(node))
      end

      # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def normalize_element(nk_node, parent:, depth:, path:, chrome:)
        return unless nk_node.respond_to?(:name)
        return unless nk_node.element?

        tag = Html2rss::Html::Probe.tag(nk_node)
        return if STRIPPED_TAGS.include?(tag)

        if @node_count >= MAX_NODES && !@degraded
          @degraded = true
          Html2rss::Log.warn("sst.normalizer MAX_NODES=#{MAX_NODES} breached; degrading to semantic-tag-only")
        end

        return if @degraded && !SEMANTIC_DEGRADE_TAGS.include?(tag)

        @node_count += 1
        tag_path = path.empty? ? "/#{tag}" : "#{path}/#{tag}"
        attrs = extract_attrs(nk_node)
        own_text = direct_text(nk_node)
        chrome_here = chrome || IGNORED_CONTAINER_TAGS.include?(tag)

        children = nk_node.element_children.filter_map do |child|
          normalize_element(child, parent: :pending, depth: depth + 1, path: tag_path, chrome: chrome_here)
        end.freeze

        node = Node.build(name: tag, attrs:, own_text:, children:, tag_path:)
        @parents[node] = parent == :pending ? nil : parent
        @depths[node] = depth
        @ignored_chrome[node] = chrome_here

        # Fix parent pointers now that node exists.
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

      def direct_text(nk_node)
        nk_node.children.select(&:text?).map(&:text).join
      end
    end
  end
end
