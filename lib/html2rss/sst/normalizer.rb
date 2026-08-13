# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Sole Nokogiri consumer on the heuristic auto-source path. Builds an
    # immutable SST::Document with parent/depth/chrome indices.
    class Normalizer
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

      class << self
        ##
        # @param parsed_body [Nokogiri::HTML::Document, Nokogiri::XML::Node]
        # @return [Document]
        # @raise [ArgumentError] when parsed_body is nil
        def call(parsed_body)
          raise ArgumentError, 'parsed_body is required' unless parsed_body

          new(parsed_body).call
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
        root_nk = @parsed_body.respond_to?(:root) ? (@parsed_body.at_css('html') || @parsed_body.root) : @parsed_body
        root = normalize_element(root_nk, parent: nil, depth: 0, path: '', chrome: false)
        raise ArgumentError, 'SST Normalizer produced an empty tree' unless root

        index = Index.new(root:, parents: @parents, depths: @depths, ignored_chrome: @ignored_chrome)
        Document.build(root:, index:, degraded: @degraded, node_count: @node_count)
      end

      private

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def normalize_element(nk_node, parent:, depth:, path:, chrome:)
        return unless nk_node.respond_to?(:name)
        return if nk_node.text? || nk_node.comment? || nk_node.cdata?

        tag = nk_node.name.to_s.downcase
        return if STRIPPED_TAGS.include?(tag)
        return if @degraded && !SEMANTIC_DEGRADE_TAGS.include?(tag)

        if @node_count >= MAX_NODES && !@degraded
          @degraded = true
          Html2rss::Log.warn("sst.normalizer MAX_NODES=#{MAX_NODES} breached; degrading to semantic-tag-only")
        end

        return if @degraded && !SEMANTIC_DEGRADE_TAGS.include?(tag)

        @node_count += 1
        tag_path = path.empty? ? "/#{tag}" : "#{path}/#{tag}"
        attrs = extract_attrs(nk_node)
        own_text = direct_text(nk_node)
        chrome_here = chrome || Tags::IGNORED_CONTAINER_NAMES.include?(tag.to_sym)

        children = nk_node.children.filter_map do |child|
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
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      def extract_attrs(nk_node) = AttrBuilder.call(nk_node)

      def direct_text(nk_node)
        nk_node.children.select(&:text?).map(&:text).join
      end
    end
  end
end
