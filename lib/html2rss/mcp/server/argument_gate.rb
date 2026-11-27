# frozen_string_literal: true

module Html2rss
  module MCP
    module Server
      ##
      # Mixed into the protocol server so argument errors come back as the envelope, not the SDK's plain text.
      #
      # The SDK rejects missing or schema-breaking arguments before a tool runs. This checks the same published
      # input schema first and answers with {Outcome.from_error} (+next_step+ +validate+), so every tool fails
      # one way and the schemas stay as published.
      #
      # Depends on the mcp gem's +Server#call_tool(request)+ entry point, +tools[name].input_schema+ and its plain-text
      # rejection; +argument_gate_spec.rb+ pins all three.
      module ArgumentGate
        ##
        # @param request [Hash] the +tools/call+ params
        # @return [Hash] the tool result
        def call_tool(request, **)
          problem = argument_problem(tools[request[:name]], request[:arguments] || {})
          return super unless problem

          error = Contract::InvalidArgumentsError.new(problem)
          Contract.response(Outcome.from_error(error, url: request.dig(:arguments, :url))).to_h
        end

        private

        def argument_problem(tool, arguments)
          schema = tool&.input_schema
          return unless schema

          missing = schema.missing_required_arguments(arguments)
          return "Missing required arguments: #{missing.join(', ')}" if missing.any?

          schema.validate_arguments(arguments)
          nil
        rescue ::MCP::Tool::InputSchema::ValidationError => error
          error.message
        end
      end
    end
  end
end
