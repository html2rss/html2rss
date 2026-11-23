# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Shared empty defaults for {Attrs} (kept outside Data.define for constant visibility).
    module AttrDefaults
      # Shared empty class_names array for Attrs defaults.
      EMPTY_CLASS_NAMES = [].freeze
      # Shared empty raw attribute hash for Attrs defaults.
      EMPTY_RAW = {}.freeze
    end

    Attrs = Data.define(
      :href, :src, :id, :class_names, :datetime, :itemprop, :style, :srcset, :type, :raw
    )

    ##
    # Typed HTML attributes for an SST node. Absent fields are +nil+.
    class Attrs
      class << self
        ##
        # @param href [String, nil]
        # @param src [String, nil]
        # @param id [String, nil]
        # @param class_names [Array<String>, nil] an Array of Strings is frozen in place, so +Attrs+ takes
        #   ownership of it
        # @param datetime [String, nil]
        # @param itemprop [String, nil]
        # @param style [String, nil]
        # @param srcset [String, nil]
        # @param type [String, nil]
        # @param raw [Hash{String => String}, nil] a Hash of frozen Strings is frozen in place, so +Attrs+
        #   takes ownership of it
        # @return [Attrs]
        # rubocop:disable-next Metrics/MethodLength, Metrics/ParameterLists
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

        ##
        # @return [Attrs]
        def empty = EMPTY_ATTRS

        private

        def blank_to_nil(value)
          return if value.nil?

          stripped = value.to_s.strip
          stripped.freeze unless stripped.empty?
        end

        def normalize_class_names(class_names)
          case class_names
          when nil then AttrDefaults::EMPTY_CLASS_NAMES
          when Array then freeze_tokens(class_names)
          else raise InvalidError, "class_names must be an Array, got #{class_names.class}"
          end
        end

        def freeze_tokens(tokens)
          return AttrDefaults::EMPTY_CLASS_NAMES if tokens.empty?
          return tokens.each(&:freeze).freeze if tokens.all?(String)

          tokens.map { |token| token.to_s.freeze }.freeze
        end

        def freeze_raw(raw)
          return AttrDefaults::EMPTY_RAW if raw.empty?
          return raw.freeze if raw.all? { |_, value| value.is_a?(String) && value.frozen? }

          raw.transform_values { |value| value.to_s.freeze }.freeze
        end

        def normalize_raw(raw)
          case raw
          when nil then AttrDefaults::EMPTY_RAW
          when Hash then freeze_raw(raw)
          else raise InvalidError, "raw must be a Hash, got #{raw.class}"
          end
        end
      end

      ##
      # @return [String]
      def class_attr = class_names.join(' ')
    end

    # Shared empty Attrs instance for nodes without attributes.
    EMPTY_ATTRS = Attrs.new(
      href: nil, src: nil, id: nil, class_names: AttrDefaults::EMPTY_CLASS_NAMES, datetime: nil,
      itemprop: nil, style: nil, srcset: nil, type: nil, raw: AttrDefaults::EMPTY_RAW
    ).freeze
  end
end
