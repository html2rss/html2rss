# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Batch do
  describe '.map' do
    it 'processes items concurrently preserving input order', :aggregate_failures do
      results = described_class.map([1, 2, 3, 4], concurrency: 2) do |item|
        item * 2
      end

      expect(results).to eq([2, 4, 6, 8])
    end

    it 'handles an empty list' do
      expect(described_class.map([])).to eq([])
    end

    it 'bounds concurrency between 1 and MAX_CONCURRENCY', :aggregate_failures do
      expect(described_class.map([1], concurrency: 0) { |x| x }).to eq([1])
      expect(described_class.map([1, 2], concurrency: 100) { |x| x }).to eq([1, 2])
    end
  end

  describe '.run' do
    # rubocop:disable RSpec/ExampleLength
    it 'returns a BatchResult with total and successful counts', :aggregate_failures do
      result = described_class.run(['https://example.com/a', 'https://example.com/b'], concurrency: 2) do |url|
        if url.end_with?('b')
          { url:, ok: false, error: 'Failed' }
        else
          { url:, ok: true, items_count: 3 }
        end
      end

      expect(result).to be_a(described_class::BatchResult)
      expect(result.total).to eq(2)
      expect(result.successful).to eq(1)
      expect(result.results.size).to eq(2)
      expect(result.to_h).to eq(
        total: 2,
        successful: 1,
        results: [
          { url: 'https://example.com/a', ok: true, items_count: 3 },
          { url: 'https://example.com/b', ok: false, error: 'Failed' }
        ]
      )
    end
    # rubocop:enable RSpec/ExampleLength
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

  describe '.inspect_urls' do
    let(:urls) { ['https://example.com/one', 'https://example.com/two'] }

    before do
      allow(Html2rss::Recon).to receive(:call) do |url, strategy:| # rubocop:disable Lint/UnusedBlockArgument
        raise StandardError, 'Connection failed' if url.include?('two')

        instance_double(
          Html2rss::Recon::Result,
          status: 200,
          final_url: Html2rss::Url.from_absolute(url),
          verdict: Html2rss::Recon::Verdict.coerce(:build),
          native_feed: nil,
          surface_category: Html2rss::SurfaceCategory.coerce(:article_list),
          articles_count: 5
        )
      end
    end

    # rubocop:disable RSpec/ExampleLength
    it 'inspects URLs in parallel and isolates per-URL errors', :aggregate_failures do
      result = described_class.inspect_urls(urls:, strategy: :auto, concurrency: 2)

      expect(result.total).to eq(2)
      expect(result.successful).to eq(1)

      first = result.results.first
      expect(first[:url]).to eq('https://example.com/one')
      expect(first[:ok]).to be(true)
      expect(first[:status_code]).to eq(200)
      expect(first[:verdict]).to eq(:build)

      second = result.results.last
      expect(second[:url]).to eq('https://example.com/two')
      expect(second[:ok]).to be(false)
      expect(second[:error]).to eq('Connection failed')
    end
    # rubocop:enable RSpec/ExampleLength
  end
end
