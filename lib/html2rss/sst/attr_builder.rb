# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Builds typed Attrs from a Nokogiri element (Normalizer-only helper).
    module AttrBuilder
      # Attribute names promoted into typed Attrs fields (remainder goes to raw).
      TYPED_ATTR_NAMES = %w[href src id class datetime itemprop style srcset type].to_set.freeze

      module_function

      ##
      # @param nk_node [Nokogiri::XML::Node]
      # @return [Attrs]
      def call(nk_node) # rubocop:disable Metrics/MethodLength
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
          next unless name.match?(Normalizer::RAW_ATTR_KEEP)

          raw[name] = attr.value.to_s
        end
      end
      module_function :raw_attrs
      private_class_method :raw_attrs
    end
  end
end
