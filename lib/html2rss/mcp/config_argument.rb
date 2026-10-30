# frozen_string_literal: true

module Html2rss
  module MCP
    ConfigArgument = Data.define(:config)

    # Feed config supplied over MCP as a hash XOR a YAML string.
    #
    # Config does not know MCP. YAML parsing stays on {Html2rss::Config.from_yaml}.
    class ConfigArgument
      class << self
        ##
        # @param config [Hash, nil] feed configuration hash
        # @param yaml [String, nil] feed configuration YAML
        # @return [ConfigArgument]
        # @raise [ArgumentError] unless exactly one of +config+ or +yaml+ is present
        # @raise [Html2rss::InvalidOption] when +config+ is not a Hash or +yaml+ is not a String
        # @raise [Contract::UnpublishedRequestError] when the parsed config uses
        #   an unpublished MCP strategy or +request.local_file_path+
        def parse(config: nil, yaml: nil)
          parsed = case [present?(config), present?(yaml)]
                   in [true, false]
                     HashUtil.deep_symbolize_keys(require_type!(config, Hash, 'config'), context: 'config')
                   in [false, true]
                     Config.from_yaml(require_type!(yaml, String, 'yaml'))
                   else
                     raise ArgumentError, 'Provide exactly one of config or yaml'
                   end
          Contract.assert_published_request!(parsed)
          new(config: parsed)
        end

        private

        def require_type!(value, type, name)
          return value if value.is_a?(type)

          raise Html2rss::InvalidOption, "#{name} must be a #{type}, got #{value.class}"
        end

        def present?(value)
          case value
          in nil then false
          in String then !value.strip.empty?
          else true
          end
        end
      end
    end
  end
end
