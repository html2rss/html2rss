# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::MCP do
  it 'is a Module' do
    expect(described_class).to be_a(Module)
  end

  describe '.start' do
    before do
      allow(Html2rss::MCP::Server).to receive(:start)
    end

    it 'delegates to Server.start' do
      described_class.start(transport: :stdio, port: 8080)

      expect(Html2rss::MCP::Server).to have_received(:start).with(transport: :stdio, port: 8080)
    end
  end
end
