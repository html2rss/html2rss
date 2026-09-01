# frozen_string_literal: true

module Html2rss
  ##
  # MCP server for AI client consumption.
  #
  # {include:file:lib/html2rss/mcp/README.md}
  #
  # Lazy-loads the mcp gem; no cost when the server is not started.
  module MCP
    class << self
      ##
      # Starts the MCP server using the given transport.
      #
      # @param transport [Symbol] +:stdio+ or +:http+
      # @param port [Integer] port for HTTP transport (bound to 127.0.0.1)
      def start(transport: :stdio, port: 8080)
        require 'mcp'
        require_relative 'mcp/server'
        Server.start(transport:, port:)
      end
    end
  end
end
