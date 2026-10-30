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

    it 'rejects an empty or non-Array item list', :aggregate_failures do
      [[], nil, 'ab', 1..2].each do |items|
        expect { described_class.map(items) { |x| x } }
          .to raise_error(Html2rss::InvalidOption, /\Aitems must be a non-empty Array/)
      end
    end

    it 'rejects concurrency outside 1..MAX_CONCURRENCY or not an Integer', :aggregate_failures do
      [0, -1, described_class::MAX_CONCURRENCY + 1, nil, '3', 2.5].each do |concurrency|
        expect { described_class.map([1], concurrency:) { |x| x } }
          .to raise_error(Html2rss::InvalidOption, /concurrency must be an Integer in 1\.\.10/)
      end
    end

    it 'accepts the concurrency bounds', :aggregate_failures do
      expect(described_class.map([1], concurrency: 1) { |x| x }).to eq([1])
      expect(described_class.map([1], concurrency: described_class::MAX_CONCURRENCY) { |x| x }).to eq([1])
    end

    it 'returns only after every slow item has finished' do
      results = described_class.map([1, 2, 3], concurrency: 3) do |item|
        sleep 0.05
        item
      end

      expect(results).to eq([1, 2, 3])
    end

    it 'caps workers at the item count' do
      allow(Thread).to receive(:new).and_call_original
      described_class.map([1, 2, 3, 4], concurrency: 10) { |item| item }
      expect(Thread).to have_received(:new).exactly(4).times
    end

    it 'uses the requested concurrency when it is inside the bounds' do
      allow(Thread).to receive(:new).and_call_original
      described_class.map((1..8).to_a, concurrency: 3) { |item| item }
      expect(Thread).to have_received(:new).exactly(3).times
    end
  end

  describe '.run' do
    # rubocop:disable-next RSpec/ExampleLength
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

    it 'uses the default worker count when concurrency is omitted' do
      allow(described_class).to receive(:map).and_call_original
      described_class.run([1]) { |item| item }
      expect(described_class).to have_received(:map).with([1], concurrency: described_class::DEFAULT_CONCURRENCY)
    end

    it 'rejects a bare value instead of wrapping it' do
      expect { described_class.run('ab') { |item| item } }.to raise_error(Html2rss::InvalidOption)
    end

    it 'counts present non-hash results and ignores a false ok flag' do
      special = Class.new(Hash).new
      special[:ok] = false
      result = described_class.run([special, nil, 'kept', 'also', {}]) { |item| item }
      expect(result.successful).to eq(2)
    end
  end

  describe '.batch_scrape' do
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
                                                   .and_raise(Html2rss::Error, 'Scrape timed out')
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'scrapes URLs in parallel and records structured items and errors', :aggregate_failures do
      result = described_class.batch_scrape(urls:, strategy: :auto, limit: 10, concurrency: 2)

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

    # rubocop:disable-next RSpec/ExampleLength
    it 'records the exact per-URL hash for success and failure', :aggregate_failures do
      expect(described_class.batch_scrape(urls:, concurrency: 2).results).to eq(
        [
          { url: 'https://example.com/a', ok: true, items_count: 1,
            items: [{ title: 'Item 1', url: 'https://example.com/a/1' }], channel_title: 'Feed A' },
          { url: 'https://example.com/b', ok: false, error: 'Scrape timed out' }
        ]
      )
    end

    it 'defaults to the auto strategy, a limit of 10 and the default worker count', :aggregate_failures do
      allow(described_class).to receive(:run).and_call_original
      described_class.batch_scrape(urls:)

      expect(Html2rss).to have_received(:auto_feed_result).with('https://example.com/a', strategy: :auto, limit: 10)
      expect(described_class).to have_received(:run).with(urls, concurrency: described_class::DEFAULT_CONCURRENCY)
    end

    it 'rejects a non-positive or non-Integer limit before scraping', :aggregate_failures do
      [0, -1, '5'].each do |limit|
        expect { described_class.batch_scrape(urls:, limit:) }
          .to raise_error(Html2rss::InvalidOption, /limit must be an Integer in 1\.\./)
      end
      expect(Html2rss).not_to have_received(:auto_feed_result)
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'accepts a limit of 1 and forwards it to the scraper', :aggregate_failures do
      feed = instance_double(Html2rss::FeedResult, to_json_feed: { items: [] },
                                                   status: Html2rss::Status.build(articles: []))
      allow(Html2rss).to receive(:auto_feed_result).with('https://example.com/a', strategy: :auto, limit: 1)
                                                   .and_return(feed)
      result = described_class.batch_scrape(urls: urls.first(1), limit: 1)

      expect(result.successful).to eq(1)
      expect(Html2rss).to have_received(:auto_feed_result).with('https://example.com/a', strategy: :auto, limit: 1)
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'coerces a string strategy to a symbol before scraping', :aggregate_failures do
      feed = instance_double(Html2rss::FeedResult, to_json_feed: { items: [] },
                                                   status: Html2rss::Status.build(articles: []))
      allow(Html2rss).to receive(:auto_feed_result).with('https://example.com/a', strategy: :default, limit: 10)
                                                   .and_return(feed)
      described_class.batch_scrape(urls: urls.first(1), strategy: 'default')

      expect(Html2rss).to have_received(:auto_feed_result).with('https://example.com/a', strategy: :default, limit: 10)
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'reports a non-String URL as its string form', :aggregate_failures do
      feed = instance_double(Html2rss::FeedResult, to_json_feed: { items: [] },
                                                   status: Html2rss::Status.build(articles: []))
      allow(Html2rss).to receive(:auto_feed_result).and_return(feed)
      result = described_class.batch_scrape(urls: [:'https://example.com/a'])

      expect(result.results).to eq([{ url: 'https://example.com/a', ok: true, items_count: 0, items: [],
                                      channel_title: nil }])
    end

    it 'rejects an unknown strategy before scraping', :aggregate_failures do
      expect { described_class.batch_scrape(urls:, strategy: 'bogus') }
        .to raise_error(Html2rss::InvalidOption, /strategy must be one of/)
      expect(Html2rss).not_to have_received(:auto_feed_result)
    end

    it 'lets errors that are not Html2rss::Error propagate' do
      allow(Html2rss).to receive(:auto_feed_result).and_raise(RuntimeError, 'boom')
      expect { described_class.batch_scrape(urls: urls.first(1)) }.to raise_error(RuntimeError, 'boom')
    end
  end

  describe '.scrape_wire' do
    let(:status) { Html2rss::Status.build(articles: [], admission_drops: { 'duplicate' => 2 }) }
    let(:feed_result) do
      instance_double(Html2rss::FeedResult, status:, to_json_feed: { title: 'Feed', items: [{ title: 'Item' }] })
    end

    before { allow(Html2rss).to receive(:auto_feed_result).and_return(feed_result) }

    it 'returns the coerced strategy, items, channel title and admission drops', :aggregate_failures do
      result = described_class.scrape_wire(url: 'https://example.com', strategy: 'default', limit: 3)

      expect(result).to eq(strategy: :default, items: [{ title: 'Item' }], channel_title: 'Feed',
                           admission_drops: { 'duplicate' => 2 })
      expect(Html2rss).to have_received(:auto_feed_result).with('https://example.com', strategy: :default, limit: 3)
    end

    it 'forwards items_selector only when it is given', :aggregate_failures do
      described_class.scrape_wire(url: 'https://example.com', strategy: :auto, limit: 10, items_selector: '.card')
      expect(Html2rss).to have_received(:auto_feed_result)
        .with('https://example.com', strategy: :auto, limit: 10, items_selector: '.card')

      described_class.scrape_wire(url: 'https://example.com', strategy: :auto, limit: 10)
      expect(Html2rss).to have_received(:auto_feed_result).with('https://example.com', strategy: :auto, limit: 10).once
    end

    it 'returns no items and a nil title when the feed has neither', :aggregate_failures do
      allow(feed_result).to receive(:to_json_feed).and_return({})
      expect(described_class.scrape_wire(url: 'https://example.com', strategy: :auto, limit: 1))
        .to include(items: [], channel_title: nil)
    end

    it 'rejects an unknown strategy' do
      expect { described_class.scrape_wire(url: 'https://example.com', strategy: 'bogus', limit: 1) }
        .to raise_error(Html2rss::InvalidOption, /strategy must be one of/)
    end
  end

  describe '.batch_inspect' do
    let(:urls) { ['https://example.com/one', 'https://example.com/two'] }

    before do
      allow(Html2rss::PageRecon::Diagnostics).to receive(:batch).with(urls:, strategy: :auto, concurrency: 2) do
        [
          Html2rss::PageRecon::Diagnostics::Report.new(
            data: {
              requested_url: 'https://example.com/one',
              final_url: 'https://example.com/one',
              status: 200,
              alternate_feeds: [],
              articles_count: 5,
              scheme_downgrade: false,
              surface_category: :article_list,
              html_response: true,
              content_type: 'text/html',
              strategy: :auto,
              scraper_eligibility: []
            }
          ),
          Html2rss::PageRecon::Diagnostics::Report.new(
            data: {
              requested_url: 'https://example.com/two',
              final_url: 'https://example.com/two',
              status: nil,
              alternate_feeds: [],
              articles_count: 0,
              scheme_downgrade: false,
              surface_category: :unsupported_surface,
              html_response: false,
              content_type: nil,
              strategy: :auto,
              scraper_eligibility: { error: 'StandardError - Connection failed' }
            }
          )
        ]
      end
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'inspects URLs in parallel and isolates per-URL errors', :aggregate_failures do
      result = described_class.batch_inspect(urls:, strategy: :auto, concurrency: 2)

      expect(result.total).to eq(2)
      expect(result.successful).to eq(1)

      first = result.results.first
      expect(first[:requested_url]).to eq('https://example.com/one')
      expect(first[:status]).to eq(200)

      second = result.results.last
      expect(second[:requested_url]).to eq('https://example.com/two')
      expect(second[:status]).to be_nil
      expect(second[:scraper_eligibility]).to include(error: 'StandardError - Connection failed')
    end

    # rubocop:disable-next RSpec/ExampleLength -- 399, 400, and a missing status share one count
    it 'counts a status of 399 and rejects 400 or a missing status' do
      allow(Html2rss::PageRecon::Diagnostics).to receive(:batch).and_return(
        [
          Html2rss::PageRecon::Diagnostics::Report.new(data: { status: 399 }),
          Html2rss::PageRecon::Diagnostics::Report.new(data: { status: 400 }),
          Html2rss::PageRecon::Diagnostics::Report.new(data: {})
        ]
      )
      result = described_class.batch_inspect(urls: ['https://example.com/edge'], strategy: :auto)
      expect(result.successful).to eq(1)
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'coerces a string strategy and rejects an empty URL list', :aggregate_failures do
      allow(Html2rss::PageRecon::Diagnostics).to receive(:batch).and_return([])
      described_class.batch_inspect(urls:, strategy: 'botasaurus')

      expect(Html2rss::PageRecon::Diagnostics).to have_received(:batch)
        .with(urls:, strategy: :botasaurus, concurrency: described_class::DEFAULT_CONCURRENCY)
      expect { described_class.batch_inspect(urls: []) }
        .to raise_error(Html2rss::InvalidOption, /urls must be a non-empty Array/)
    end

    it 'uses auto and the default worker count when strategy and concurrency are omitted' do
      allow(Html2rss::PageRecon::Diagnostics).to receive(:batch).and_return([])
      described_class.batch_inspect(urls:)
      expect(Html2rss::PageRecon::Diagnostics).to have_received(:batch).with(
        urls:, strategy: :auto, concurrency: described_class::DEFAULT_CONCURRENCY
      )
    end
  end

  describe '.batch_recon' do
    let(:urls) { ['https://example.com/one', 'https://example.com/two'] }

    before do
      allow(Html2rss::Recon).to receive(:batch).with(urls, strategy: :auto, max_threads: 2) do
        [
          Html2rss::Recon::Result.new(
            requested_url: Html2rss::Url.from_absolute('https://example.com/one'),
            final_url: Html2rss::Url.from_absolute('https://example.com/one'),
            status: 200,
            verdict: Html2rss::Recon::Verdict[:build],
            native_feed: nil,
            surface_category: Html2rss::SurfaceCategory[:listing],
            articles_count: 5,
            scheme_downgrade: false,
            notes: [],
            html_bytesize: 1024
          ),
          Html2rss::Recon::Result.new(
            requested_url: Html2rss::Url.from_absolute('https://example.com/two'),
            final_url: Html2rss::Url.from_absolute('https://example.com/two'),
            status: nil,
            verdict: Html2rss::Recon::Verdict[:drop],
            native_feed: nil,
            surface_category: Html2rss::SurfaceCategory[:unsupported_surface],
            articles_count: 0,
            scheme_downgrade: false,
            notes: ['error: StandardError - Connection failed'],
            html_bytesize: nil
          )
        ]
      end
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'recons URLs in parallel and isolates per-URL errors', :aggregate_failures do
      result = described_class.batch_recon(urls:, strategy: :auto, concurrency: 2)

      expect(result.total).to eq(2)
      expect(result.successful).to eq(1)

      first = result.results.first
      expect(first[:requested_url]).to eq('https://example.com/one')
      expect(first[:status]).to eq(200)
      expect(first[:verdict]).to eq(:build)

      second = result.results.last
      expect(second[:requested_url]).to eq('https://example.com/two')
      expect(second[:status]).to be_nil
      expect(second[:verdict]).to eq(:drop)
      expect(second[:notes]).to eq(['error: StandardError - Connection failed'])
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'rejects a concurrency outside 1..MAX_CONCURRENCY and an empty URL list', :aggregate_failures do
      [0, described_class::MAX_CONCURRENCY + 1, '2'].each do |concurrency|
        expect { described_class.batch_recon(urls:, concurrency:) }
          .to raise_error(Html2rss::InvalidOption, /concurrency must be an Integer in 1\.\.10/)
      end
      expect { described_class.batch_recon(urls: []) }
        .to raise_error(Html2rss::InvalidOption, /urls must be a non-empty Array/)
    end

    it 'uses auto and the default worker count when strategy and concurrency are omitted' do
      allow(Html2rss::Recon).to receive(:batch).and_return([])
      described_class.batch_recon(urls:, cache_dir: '/tmp/recon-cache')
      expect(Html2rss::Recon).to have_received(:batch).with(
        urls, strategy: :auto, max_threads: described_class::DEFAULT_CONCURRENCY, cache_dir: '/tmp/recon-cache'
      )
    end

    it 'symbolizes a string strategy and treats nil as auto', :aggregate_failures do
      allow(Html2rss::Recon).to receive(:batch).and_return([])
      described_class.batch_recon(urls:, strategy: 'botasaurus', concurrency: 2)
      described_class.batch_recon(urls:, strategy: nil, concurrency: 2)
      expect(Html2rss::Recon).to have_received(:batch).with(urls, strategy: :botasaurus, max_threads: 2)
      expect(Html2rss::Recon).to have_received(:batch).with(urls, strategy: :auto, max_threads: 2)
    end

    # rubocop:disable-next RSpec/ExampleLength -- 399, 400, and a missing status share one count
    it 'counts a status of 399 and rejects 400 or a missing status' do
      allow(Html2rss::Recon).to receive(:batch).and_return(
        [
          instance_double(Html2rss::Recon::Result, status: 399, to_h: { status: 399 }),
          instance_double(Html2rss::Recon::Result, status: 400, to_h: { status: 400 }),
          instance_double(Html2rss::Recon::Result, status: nil, to_h: {})
        ]
      )
      result = described_class.batch_recon(urls:, concurrency: 1)
      expect(result.successful).to eq(1)
    end
  end
end
