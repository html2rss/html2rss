# frozen_string_literal: true

module Html2rss
  module MCP
    # Feed config supplied over MCP as a hash XOR a YAML string.
    #
    # Config does not know MCP. YAML parsing stays on {Html2rss::Config.from_yaml}.
    ConfigArgument = Data.define(:config) do
      class << self
        ##
        # @param config [Hash, nil] feed configuration hash
        # @param yaml [String, nil] feed configuration YAML
        # @return [ConfigArgument]
        # @raise [ArgumentError] unless exactly one of +config+ or +yaml+ is present
        def parse(config: nil, yaml: nil)
          case [present?(config), present?(yaml)]
          in [true, false]
            new(config: HashUtil.deep_symbolize_keys(config, context: 'config'))
          in [false, true]
            new(config: Config.from_yaml(yaml))
          else
            raise ArgumentError, 'Provide exactly one of config or yaml'
          end
        end

        private

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
