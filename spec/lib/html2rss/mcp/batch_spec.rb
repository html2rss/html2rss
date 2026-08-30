# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::MCP::Batch do
  describe '.inspect_urls' do
    let(:urls) { ['https://example.com/one', 'https://example.com/two'] }

    before do
      allow(Html2rss::MCP::Inspect).to receive(:call) do |url:, strategy:| # rubocop:disable Lint/UnusedBlockArgument
        raise StandardError, 'Connection failed' if url.include?('two')

        { status: 200, final_url: url, alternate_feeds: [{ href: "#{url}/feed.xml" }] }
      end
    end

    # rubocop:disable RSpec/ExampleLength
    it 'processes URLs in parallel and isolates per-URL errors', :aggregate_failures do
      result = described_class.inspect_urls(urls:, strategy: :auto, concurrency: 2)

      expect(result.total).to eq(2)
      expect(result.successful).to eq(1)
      expect(result.results.size).to eq(2)

      first = result.results.first
      expect(first[:url]).to eq('https://example.com/one')
      expect(first[:ok]).to be(true)
      expect(first[:status_code]).to eq(200)
      expect(first[:alternate_feeds]).to eq([{ href: 'https://example.com/one/feed.xml' }])

      second = result.results.last
      expect(second[:url]).to eq('https://example.com/two')
      expect(second[:ok]).to be(false)
      expect(second[:error]).to eq('Connection failed')
    end
    # rubocop:enable RSpec/ExampleLength

    it 'handles an empty url list', :aggregate_failures do
      result = described_class.inspect_urls(urls: [])

      expect(result.total).to eq(0)
      expect(result.successful).to eq(0)
      expect(result.results).to be_empty
    end
  end

  describe '.scrape_urls' do
    let(:urls) { ['https://example.com/a', 'https://example.com/b'] }

    before do
      status = Html2rss::Status.build(articles: [], dedup_dropped: 0, admission_drops: {})
      feed_result_a = instance_double(
        Html2rss::FeedResult,
        to_json_feed: { title: 'Feed A', items: [{ title: 'Item 1', url: 'https://example.com/a/1' }] },
        status:
      )
      allow(Html2rss).to receive(:auto_feed_result).with('https://example.com/a', strategy: :auto, limit: 10)
                                                   .and_return(feed_result_a)
      allow(Html2rss).to receive(:auto_feed_result).with('https://example.com/b', strategy: :auto, limit: 10)
                                                   .and_raise(StandardError, 'Scrape timed out')
    end

    # rubocop:disable RSpec/ExampleLength
    it 'scrapes URLs in parallel and records structured items and errors', :aggregate_failures do
      result = described_class.scrape_urls(urls:, strategy: :auto, limit: 10, concurrency: 2)

      expect(result.total).to eq(2)
      expect(result.successful).to eq(1)

      first = result.results.first
      expect(first[:ok]).to be(true)
      expect(first[:channel_title]).to eq('Feed A')
      expect(first[:items_count]).to eq(1)
      expect(first[:items]).to eq([{ title: 'Item 1', url: 'https://example.com/a/1' }])

      second = result.results.last
      expect(second[:ok]).to be(false)
      expect(second[:error]).to eq('Scrape timed out')
    end
    # rubocop:enable RSpec/ExampleLength
  end
end
