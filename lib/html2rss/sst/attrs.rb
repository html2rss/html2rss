# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Shared empty defaults for {Attrs} (kept outside Data.define for constant visibility).
    module AttrDefaults
      EMPTY_CLASS_NAMES = [].freeze
      EMPTY_RAW = {}.freeze
    end

    ##
    # Typed HTML attributes for an SST node. Absent fields are +nil+.
    Attrs = Data.define(
      :href, :src, :id, :class_names, :datetime, :itemprop, :style, :srcset, :type, :raw
    ) do
      class << self
        ##
        # @return [Attrs]
        # rubocop:disable Metrics/MethodLength, Metrics/ParameterLists
        def build(href: nil, src: nil, id: nil, class_names: nil, datetime: nil, itemprop: nil,
                  style: nil, srcset: nil, type: nil, raw: nil)
          new(
            href: blank_to_nil(href),
            src: blank_to_nil(src),
            id: blank_to_nil(id),
            class_names: normalize_class_names(class_names),
            datetime: blank_to_nil(datetime),
            itemprop: blank_to_nil(itemprop),
            style: blank_to_nil(style),
            srcset: blank_to_nil(srcset),
            type: blank_to_nil(type),
            raw: normalize_raw(raw)
          )
        end
        # rubocop:enable Metrics/MethodLength, Metrics/ParameterLists

        ##
        # @return [Attrs]
        def empty = EMPTY_ATTRS

        private

        def blank_to_nil(value)
          str = value&.to_s
          return if str.nil? || str.strip.empty?

          str.strip.freeze
        end

        def normalize_class_names(class_names)
          case class_names
          when nil then AttrDefaults::EMPTY_CLASS_NAMES
          when Array then class_names.map { |token| token.to_s.freeze }.freeze
          else raise ArgumentError, "class_names must be an Array, got #{class_names.class}"
          end
        end

        def normalize_raw(raw)
          case raw
          when nil then AttrDefaults::EMPTY_RAW
          when Hash then raw.transform_values { |v| v.to_s.freeze }.freeze
          else raise ArgumentError, "raw must be a Hash, got #{raw.class}"
          end
        end
      end

      ##
      # @return [String]
      def class_attr = class_names.join(' ')
    end

    EMPTY_ATTRS = Attrs.new(
      href: nil, src: nil, id: nil, class_names: AttrDefaults::EMPTY_CLASS_NAMES, datetime: nil,
      itemprop: nil, style: nil, srcset: nil, type: nil, raw: AttrDefaults::EMPTY_RAW
    ).freeze
  end
end
