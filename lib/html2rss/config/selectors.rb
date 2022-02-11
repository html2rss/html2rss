module Html2rss
  class Config
    ##
    # Holds the configuration for the selectors in the config.
    class Selectors
      def initialize(feed_config, params)
        symbolized_params = params.transform_keys(&:to_sym)

        assert_required_params_presence(feed_config, symbolized_params)

        @feed_config = process_params(feed_config, symbolized_params)
      end

      ##
      # @param name [Symbol]
      # @return [Hash]
      def attribute_options(name)
        feed_config[:selectors].fetch(name, {}).merge(channel: feed_config[:channel])
      end

      ##
      # @param name [Symbol]
      # @return [true, false]
      def attribute?(name)
        attribute_names.include?(name)
      end

      ##
      # @return [Array<Symbol>]
      def category_selectors
        selector_names_for(:categories)
      end

      ##
      # @return [Array<Symbol>]
      def guid_selectors
        selector_names_for(:guid, default: :title_or_description)
      end

      ##
      # @param name [Symbol]
      # @return [String]
      def selector(name)
        feed_config.dig(:selectors, name, :selector)
      end

      ##
      # @return [Array<String>]
      def attribute_names
        @attribute_names ||= feed_config.fetch(:selectors, {}).keys.tap { |attrs| attrs.delete(:items) }
      end

      ##
      # @return [Symbol]
      def items_order
        feed_config.dig(:selectors, :items, :order)&.to_sym
      end

      # TODO: move to channel config, rename appropriately
      ##
      # Returns the dynamic parameter names which are required to use the feed config.
      #
      # @param feed_config [Hash<Symbol, Object>]
      # @return [Set] containing Strings (the parameter names)
      def self.required_params_for_feed_config(feed_config)
        raise ChannelMissing, 'feed config misses :channel key' unless feed_config[:channel]

        Set.new.tap do |required_params|
          feed_config[:channel].each_key do |attribute_name|
            next unless feed_config[:channel][attribute_name].is_a?(String)

            required_params.merge feed_config[:channel][attribute_name].scan(/%<([\w_\d]+)>(\w)?/).to_h.keys
          end
        end
      end

      private

      attr_reader :feed_config

      ##
      # @param feed_config [Hash<Symbol, Object>]
      # @param params [Hash<Symbol, String>]
      # @return [nil]
      def assert_required_params_presence(feed_config, params)
        missing_params = self.class.required_params_for_feed_config(feed_config) - params.keys.map(&:to_s)

        raise ParamsMissing, missing_params.to_a.join(', ') if missing_params.size.positive?
      end

      ##
      # Sets the variables used in the feed config's channel.
      #
      # @param feed_config [Hash<Symbol, Object>]
      # @param params [Hash<Symbol, Object>]
      # @return [Hash<Symbol, Object>]
      def process_params(feed_config, params)
        return feed_config if params.keys.none?

        # TODO: this should use the channel config instance
        feed_config[:channel].each_key do |attribute_name|
          next unless feed_config[:channel][attribute_name].is_a?(String)

          feed_config[:channel][attribute_name] = format(feed_config[:channel][attribute_name], params)
        end

        feed_config
      end

      ##
      # Returns the selector names for selector `name`. If none, returns [default].
      # @param name [Symbol]
      # @param default [String, Symbol]
      # @return [Array<Symbol>]
      def selector_names_for(name, default: nil)
        feed_config[:selectors].fetch(name) { Array(default) }.tap do |array|
          array.reject! { |entry| entry.to_s == '' }
          array.map!(&:to_sym)
          array.uniq!
        end
      end
    end
  end
end
