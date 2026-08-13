# frozen_string_literal: true

module Html2rss
  module SST
    ##
    # Typed HTML attributes for an SST node. Absent fields are +nil+; never a
    # free-form attribute Hash at stage boundaries.
    Attrs = Data.define(
      :href,
      :src,
      :id,
      :class_names,
      :datetime,
      :itemprop,
      :style,
      :srcset,
      :type,
      :raw
    ) do
      EMPTY_CLASS_NAMES = [].freeze
      EMPTY_RAW = {}.freeze

      ##
      # @param href [String, nil]
      # @param src [String, nil]
      # @param id [String, nil]
      # @param class_names [Array<String>, nil]
      # @param datetime [String, nil]
      # @param itemprop [String, nil]
      # @param style [String, nil]
      # @param srcset [String, nil]
      # @param type [String, nil]
      # @param raw [Hash{String => String}, nil] extra attrs needed for extraction (data-*, category attrs)
      # @return [Attrs]
      # @raise [ArgumentError] when class_names or raw have the wrong type
      def self.build(href: nil, src: nil, id: nil, class_names: nil, datetime: nil, itemprop: nil,
                     style: nil, srcset: nil, type: nil, raw: nil)
        names = normalize_class_names(class_names)
        raw_hash = normalize_raw(raw)

        new(
          href: blank_to_nil(href),
          src: blank_to_nil(src),
          id: blank_to_nil(id),
          class_names: names,
          datetime: blank_to_nil(datetime),
          itemprop: blank_to_nil(itemprop),
          style: blank_to_nil(style),
          srcset: blank_to_nil(srcset),
          type: blank_to_nil(type),
          raw: raw_hash
        )
      end

      ##
      # @return [Attrs] empty attrs instance
      def self.empty = @empty ||= build

      ##
      # @param value [Object, nil]
      # @return [String, nil]
      def self.blank_to_nil(value)
        str = value&.to_s
        return if str.nil? || str.strip.empty?

        str.strip.freeze
      end
      private_class_method :blank_to_nil

      def self.normalize_class_names(class_names)
        case class_names
        when nil then EMPTY_CLASS_NAMES
        when Array then class_names.map { |token| token.to_s.freeze }.freeze
        else
          raise ArgumentError, "class_names must be an Array, got #{class_names.class}"
        end
      end
      private_class_method :normalize_class_names

      def self.normalize_raw(raw)
        case raw
        when nil then EMPTY_RAW
        when Hash then raw.transform_values { |v| v.to_s.freeze }.freeze
        else
          raise ArgumentError, "raw must be a Hash, got #{raw.class}"
        end
      end
      private_class_method :normalize_raw

      ##
      # @return [String] space-joined class attribute
      def class_attr = class_names.join(' ')

      ##
      # @param name [String] attribute name
      # @return [String, nil]
      def [](name)
        case name.to_s
        when 'href' then href
        when 'src' then src
        when 'id' then id
        when 'class' then class_attr.empty? ? nil : class_attr
        when 'datetime' then datetime
        when 'itemprop' then itemprop
        when 'style' then style
        when 'srcset' then srcset
        when 'type' then type
        else raw[name.to_s]
        end
      end
    end
  end
end
