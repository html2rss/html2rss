# frozen_string_literal: true

RSpec.describe Html2rss::Curation::Apply do
  let(:selector) { 'article' }
  let(:config) do
    {
      channel: { url: 'https://example.com/news', title: 'Example News' },
      strategy: :default,
      selectors: { items: { selector:, enhance: false }, title: { selector: 'h1' },
                   url: { selector: 'a', extractor: 'href' } }
    }
  end
  let(:response) do
    Html2rss::RequestService::Response.new(
      body: '<html><body><article><a href="/n/item"><h1>item</h1></a></article></body></html>',
      url: Html2rss::Url.from_absolute('https://example.com/news'),
      headers: { 'content-type' => 'text/html' },
      status: 200
    )
  end

  before do
    allow(Html2rss::RequestService).to receive(:execute) do |ctx, **|
      ctx.budget.consume!
      response
    end
  end

  describe '.call' do
    subject(:result) { described_class.call(config) }

    it 'builds one result that renders RSS, JSON Feed and status', :aggregate_failures do
      expect(result).not_to be_empty
      expect(result.item_count).to eq(1)
      expect(result.to_rss).to be_a(RSS::Rss)
      expect(result.to_json_feed).to include(:version, :items)
      expect(result.status).to be_a(Html2rss::Status)
    end

    it 'builds the RSS document once', :aggregate_failures do
      expect(result.to_rss).to equal(result.to_rss)
      expect(result.item_count).to eq(result.to_rss.items.size)
    end

    it 'audits the rendered items once, without probing the native feed', :aggregate_failures do
      allow(Html2rss::Curation::Test::Quality).to receive(:report_for).and_call_original
      expected = hash_including(channel_url: 'https://example.com/news', probe_native_feed: false)

      expect(result.quality_report).to equal(result.quality_report)
      expect(Html2rss::Curation::Test::Quality).to have_received(:report_for).once.with(result.to_rss.items, expected)
    end

    it 'forwards feed_url to the JSON Feed', :aggregate_failures do
      expect(result.to_json_feed(feed_url: 'https://example.com/feed.json')).to include(feed_url: 'https://example.com/feed.json')
      expect(result.to_json_feed).not_to have_key(:feed_url)
    end

    context 'when the selectors match nothing' do
      let(:selector) { 'section' }

      it 'returns an empty result instead of raising', :aggregate_failures do
        expect(result).to be_empty
        expect(result.item_count).to eq(0)
        expect(result.to_rss.to_s).to include('<channel>')
      end
    end

    context 'when extracted articles have nothing to render' do
      before { config[:selectors][:title] = { selector: 'h2' } }

      it 'is empty because the rendered RSS has no items', :aggregate_failures do
        expect(result.item_count).to eq(0)
        expect(result).to be_empty
      end
    end
  end
end
