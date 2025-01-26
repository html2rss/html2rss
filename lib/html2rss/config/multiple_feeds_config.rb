# frozen_string_literal: true

module Html2rss
  class Config
    ##
    # Handles multiple feeds inside one Hash. Invididual feed configuration have to be under the `feeds` key.
    # The feed name is the key of the feed configuration.
    #
    # Every information which is not under the `feeds` key, will be merged into the feed configuration.
    class MultipleFeedsConfig
      ##
      # Key for the feeds configuration in the YAML file.
      CONFIG_KEY_FEEDS = :feeds

      class << self
        def to_single_feed(config, yaml, multiple_feeds_key: CONFIG_KEY_FEEDS)
          other_keys = yaml.keys - [multiple_feeds_key]

          other_keys.each do |key|
            config[key] = merge_key(config, yaml, key)
          end

          config
        end

        private

        def merge_key(config, yaml, key)
          case config[key]
          when Hash
            yaml[key].merge(config[key])
          when Array
            yaml[key] + config[key]
          else
            yaml[key]
          end
        end
      end
    end
  end
end
