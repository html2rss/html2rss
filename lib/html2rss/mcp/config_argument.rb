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
        # @raise [Contract::UnpublishedRequestError] when the parsed config uses
        #   an unpublished MCP strategy or +request.local_file_path+
        def parse(config: nil, yaml: nil)
          parsed = case [present?(config), present?(yaml)]
                   in [true, false]
                     HashUtil.deep_symbolize_keys(config, context: 'config')
                   in [false, true]
                     Config.from_yaml(yaml)
                   else
                     raise ArgumentError, 'Provide exactly one of config or yaml'
                   end
          Contract.assert_published_request!(parsed)
          new(config: parsed)
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
