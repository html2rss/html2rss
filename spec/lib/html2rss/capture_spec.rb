# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Capture do
  let(:url) { 'https://example.com/blog' }

  def html_response(body, page_url: url)
    Html2rss::RequestService::Response.new(
      body:,
      url: Html2rss::Url.from_absolute(page_url),
      headers: { 'content-type' => 'text/html' }
    )
  end

  describe '#build' do
    context 'with a list fixture that shares an item class' do
      subject(:result) do
        instance = described_class.new(url)
        allow(instance).to receive(:fetch_response).and_return(response)
        instance.build
      end

      let(:response) { html_response(File.read('spec/fixtures/local_feed_test.html')) }

      it 'emits items selector, title hash, and channel title', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- fixture contract
        expect(result.articles_count).to eq(3)
        expect(result.config[:selectors]).to include(
          items: { selector: 'div.item' },
          title: { selector: 'h2' },
          link: { selector: 'h2 > a', extractor: 'href' }
        )
        expect(result.config[:selectors]).not_to have_key(:description)
        expect(result.config[:channel]).to include(url:, title: a_string_matching(/\S/), time_zone: 'UTC')
        expect(result.channel_title).to eq(result.config.dig(:channel, :title))
      end
    end

    {
      'drops leading html/body/div' => [
        <<~HTML,
          <html><body><div><main><section>
            <article><h2><a href="/a1">Article One Title</a></h2></article>
            <article><h2><a href="/a2">Article Two Title</a></h2></article>
            <article><h2><a href="/a3">Article Three Title</a></h2></article>
          </section></main></div></body></html>
        HTML
        'main > section > article'
      ],
      'keeps mid-path div after trim' => [
        <<~HTML,
          <html><body><main>
            <div>
              <article><h2><a href="/x1">Card One Here Longer</a></h2><p>more text here for item</p></article>
              <article><h2><a href="/x2">Card Two Here Longer</a></h2><p>more text here for item</p></article>
              <article><h2><a href="/x3">Card Three Here Longer</a></h2><p>more text here for item</p></article>
            </div>
          </main></body></html>
        HTML
        'main > div > article'
      ],
      'keeps a single remaining segment' => [
        <<~HTML,
          <html><body>
            <section><h2><a href="/s1">Section One Item</a></h2></section>
            <section><h2><a href="/s2">Section Two Item</a></h2></section>
            <section><h2><a href="/s3">Section Three Item</a></h2></section>
          </body></html>
        HTML
        'section'
      ]
    }.each do |label, (html, expected_items_selector)|
      it "trims items path: #{label}" do
        instance = described_class.new(url)
        allow(instance).to receive(:fetch_response).and_return(html_response(html))

        expect(instance.build.config.dig(:selectors, :items, :selector)).to eq(expected_items_selector)
      end
    end

    context 'when selector derivation raises ArgumentError' do
      subject(:result) { instance.build }

      let(:instance) { described_class.new(url) }
      let(:article) do
        instance_double(Html2rss::Article, url: Html2rss::Url.from_absolute("#{url}/1"), title: 'One')
      end

      before do
        allow(instance).to receive_messages(
          fetch_response: html_response('<html><body></body></html>'),
          extract_articles: [article]
        )
        allow(Html2rss::SST::Normalizer).to receive(:call).and_raise(ArgumentError, 'bad sst')
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'warns and omits selectors', :aggregate_failures do
        expect(result.config[:selectors]).to be_nil
        expect(Html2rss::Log).to have_received(:warn).with(/bad sst/)
      end
    end

    it 'analyzes a local file when local_file_path is provided', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- local overlay contract
      path = File.expand_path('spec/fixtures/local_feed_test.html')
      result = described_class.build(url, strategy: :local_file, local_file_path: path)

      expect(result.articles_count).to eq(3)
      expect(result.config.dig(:selectors, :items, :selector)).to eq('div.item')
      expect(result.config[:strategy]).to eq(:local_file)
      expect(result.config.dig(:request, :local_file_path)).to eq(path)
    end

    it 'round-trips local capture config through Html2rss.feed', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- capture→feed contract
      path = File.expand_path('spec/fixtures/local_feed_test.html')
      config = described_class.build(url, strategy: :local_file, local_file_path: path).config

      expect(config[:strategy]).to eq(:local_file)
      expect(config.dig(:request, :local_file_path)).to eq(path)
      expect(config[:selectors]).not_to have_key(:description)

      feed = Html2rss.feed(config)
      expect(feed.items.size).to eq(3)
      expect(feed.items.map(&:title)).to eq(['First Post Item', 'Second Post Item', 'Third Post Item'])
    end
  end

  describe 'Html2rss.capture' do
    let(:config_hash) { { channel: { url: 'https://example.com' } } }

    before do
      allow(described_class).to receive(:build)
        .and_return(instance_double(described_class::CaptureResult, config: config_hash))
    end

    it 'delegates to Capture.build', :aggregate_failures do
      expect(Html2rss.capture('https://example.com')).to eq(config_hash)
      expect(described_class).to have_received(:build)
        .with('https://example.com', hash_including(strategy: :auto, local_file_path: nil))
    end
  end
end
