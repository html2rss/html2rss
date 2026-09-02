# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Hash-IR → {Attrs}/{Node}/{Index}/{Document} builder (unit/debug only).
    # Path A (+HTML2RSS_HTML_BACKEND=rust+) materializes SST via Magnus directly;
    # this class stays for Hash-based specs and ad-hoc IR dumps — not the hot path.
    class Hydrator
      class << self
        ##
        # @param root_ir [Hash] nested IR (+name+, +attrs+, +own_text+, +children+,
        #   +tag_path+, +depth+, +chrome+); keys may be String or Symbol
        # @param node_count [Integer]
        # @param degraded [Boolean]
        # @return [Document]
        def call(root_ir, node_count:, degraded: false)
          new.call(root_ir, node_count:, degraded:)
        end
      end

      ##
      # @param root_ir [Hash]
      # @param node_count [Integer]
      # @param degraded [Boolean]
      # @return [Document]
      def call(root_ir, node_count:, degraded: false)
        @parents = {}.compare_by_identity
        @depths = {}.compare_by_identity
        @ignored_chrome = {}.compare_by_identity

        root = hydrate_node(root_ir, parent: nil)
        index = Index.new(root:, parents: @parents, depths: @depths, ignored_chrome: @ignored_chrome)
        Document.build(root:, index:, degraded: degraded ? true : false, node_count: Integer(node_count))
      end

      private

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- mirrors Normalizer index wiring
      def hydrate_node(node_ir, parent:)
        raise ArgumentError, 'node IR must be a Hash' unless node_ir.is_a?(Hash)

        children = Array(ir_get(node_ir, :children)).map { |child| hydrate_node(child, parent: :pending) }.freeze
        node = Node.build(
          name: ir_get(node_ir, :name),
          attrs: hydrate_attrs(ir_get(node_ir, :attrs)),
          own_text: ir_get(node_ir, :own_text),
          children:,
          tag_path: ir_get(node_ir, :tag_path)
        )

        @parents[node] = parent == :pending ? nil : parent
        @depths[node] = Integer(ir_get(node_ir, :depth) || 0)
        @ignored_chrome[node] = ir_get(node_ir, :chrome) ? true : false
        children.each { |child| @parents[child] = node }

        node
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      # rubocop:disable Metrics/MethodLength -- Attrs.build keyword surface
      def hydrate_attrs(attrs_ir)
        return Attrs.empty if attrs_ir.nil?
        raise ArgumentError, 'attrs IR must be a Hash' unless attrs_ir.is_a?(Hash)

        Attrs.build(
          href: ir_get(attrs_ir, :href),
          src: ir_get(attrs_ir, :src),
          id: ir_get(attrs_ir, :id),
          class_names: Array(ir_get(attrs_ir, :class_names)),
          datetime: ir_get(attrs_ir, :datetime),
          itemprop: ir_get(attrs_ir, :itemprop),
          style: ir_get(attrs_ir, :style),
          srcset: ir_get(attrs_ir, :srcset),
          type: ir_get(attrs_ir, :type),
          raw: ir_get(attrs_ir, :raw) || {}
        )
      end
      # rubocop:enable Metrics/MethodLength

      def ir_get(hash, key)
        hash[key] || hash[key.to_s] || hash[key.to_sym]
      end
    end
  end
end
