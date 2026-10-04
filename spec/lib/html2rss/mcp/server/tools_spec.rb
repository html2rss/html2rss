# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::MCP::Server::Tools do
  describe 'batch tool keyword defaults' do
    let(:batch_result) { Html2rss::Batch::BatchResult.new(total: 1, successful: 1, results: []) }
    let(:tools_by_name) { described_class::TOOLS.to_h { |tool| [tool.name, tool] } }

    before do
      allow(Html2rss::Batch).to receive_messages(
        batch_scrape: batch_result, batch_inspect: batch_result, batch_recon: batch_result
      )
    end

    it 'forwards batch_scrape default limit and concurrency' do
      tools_by_name.fetch('batch_scrape').call.call(urls: ['https://example.com/a'])

      expect(Html2rss::Batch).to have_received(:batch_scrape).with(
        urls: ['https://example.com/a'], strategy: :auto, limit: 10, concurrency: 5
      )
    end

    it 'forwards batch_inspect default concurrency' do
      tools_by_name.fetch('batch_inspect').call.call(urls: ['https://example.com/a'])

      expect(Html2rss::Batch).to have_received(:batch_inspect).with(
        urls: ['https://example.com/a'], strategy: :auto, concurrency: 5
      )
    end

    it 'forwards batch_recon default concurrency' do
      tools_by_name.fetch('batch_recon').call.call(urls: ['https://example.com/a'])

      expect(Html2rss::Batch).to have_received(:batch_recon).with(
        urls: ['https://example.com/a'], strategy: :auto, concurrency: 5
      )
    end
  end
end
