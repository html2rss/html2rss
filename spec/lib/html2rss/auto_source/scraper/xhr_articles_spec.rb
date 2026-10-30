# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::XhrArticles do
  let(:base_url) { Html2rss::Url.from_absolute('https://example.com') }
  let(:parsed_body) { Nokogiri::HTML('<html><body></body></html>') }
  let(:article_json) do
    [{ title: 'XHR Headline', url: '/xhr/one', description: 'From a captured fetch.' }].to_json
  end

  describe '.options_key' do
    it 'uses the xhr_articles config key' do
      expect(described_class.options_key).to eq(:xhr_articles)
    end
  end

  describe '.request_slots' do
    it 'makes no additional HTTP requests for any options', :aggregate_failures do
      expect(described_class.request_slots).to eq(0)
      expect(described_class.request_slots({ max: 5 })).to eq(0)
    end
  end

  describe '.articles?' do
    it 'is never detectable from HTML alone' do
      expect(described_class.articles?(parsed_body)).to be(false)
    end
  end

  describe '#initialize' do
    it 'resolves relative links against the page url', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      scraper = described_class.new(
        parsed_body, url: base_url, captured_responses: [{ 'body' => article_json }], _reserved: true
      )

      expect(scraper.each.to_a).to contain_exactly(
        a_hash_including(url: Html2rss::Url.from_relative('/xhr/one', base_url))
      )
    end

    it 'defaults to no captures' do
      expect(described_class.new(parsed_body, url: base_url)).not_to be_extractable
    end
  end

  describe '#extractable?' do
    it 'is true when a captured body contains article-like arrays' do # rubocop:disable RSpec/ExampleLength
      scraper = described_class.new(
        parsed_body,
        url: base_url,
        captured_responses: [{ 'body' => article_json }]
      )

      expect(scraper).to be_extractable
    end

    it 'is false when captures are empty' do
      scraper = described_class.new(parsed_body, url: base_url, captured_responses: [])

      expect(scraper).not_to be_extractable
    end

    it 'is false when JSON has no article-like arrays' do # rubocop:disable RSpec/ExampleLength
      scraper = described_class.new(
        parsed_body,
        url: base_url,
        captured_responses: [{ 'body' => '{"status":"ok"}' }]
      )

      expect(scraper).not_to be_extractable
    end

    it 'detects article-like shape before entries are normalised' do # rubocop:disable RSpec/ExampleLength
      scraper = described_class.new(
        parsed_body,
        url: base_url,
        captured_responses: [{ 'body' => [{ title: '', url: '/empty-title' }].to_json }]
      )

      expect(scraper).to be_extractable
    end
  end

  describe '#parsed_bodies' do
    it 'drops captured bodies that are not article-like' do # rubocop:disable RSpec/ExampleLength
      scraper = described_class.new(
        parsed_body,
        url: base_url,
        captured_responses: [{ 'body' => '{"status":"ok"}' }]
      )

      expect(scraper).not_to be_extractable
    end

    it 'keeps article-like bodies alongside ignored ones' do # rubocop:disable RSpec/ExampleLength
      scraper = described_class.new(
        parsed_body,
        url: base_url,
        captured_responses: [{ 'body' => '{"status":"ok"}' }, { 'body' => article_json }]
      )

      expect(scraper.each.to_a).to contain_exactly(a_hash_including(title: 'XHR Headline'))
    end
  end

  describe '#parse' do
    it 'reads the body from string-keyed captures' do
      scraper = described_class.new(parsed_body, url: base_url, captured_responses: [{ 'body' => article_json }])

      expect(scraper).to be_extractable
    end

    it 'reads the body from symbol-keyed captures' do
      scraper = described_class.new(parsed_body, url: base_url, captured_responses: [{ body: article_json }])

      expect(scraper).to be_extractable
    end

    it 'skips captures without a string body', :aggregate_failures do
      captures = [{}, { 'body' => 42 }, { 'body' => nil }, { 'other' => article_json }]
      scraper = described_class.new(parsed_body, url: base_url, captured_responses: captures)

      expect(scraper).not_to be_extractable
      expect(scraper.each.to_a).to be_empty
    end
  end

  describe '#each' do
    subject(:articles) do
      described_class.new(parsed_body, url: base_url, captured_responses:).each.to_a
    end

    context 'with article-like captured JSON' do
      let(:captured_responses) { [{ 'body' => article_json }] }

      it 'normalises observable article fields' do # rubocop:disable RSpec/ExampleLength
        expect(articles).to contain_exactly(
          a_hash_including(
            title: 'XHR Headline',
            description: 'From a captured fetch.',
            url: Html2rss::Url.from_relative('/xhr/one', base_url)
          )
        )
      end
    end

    context 'when an array mixes articles with entries that cannot be normalised' do
      let(:captured_responses) do
        [{ 'body' => [{ title: 'Kept', url: '/kept' }, { title: 'No link' }].to_json }]
      end

      it 'yields only the normalisable articles' do
        expect(articles).to contain_exactly(a_hash_including(title: 'Kept'))
      end
    end

    context 'with a non-JSON body' do
      let(:captured_responses) { [{ 'body' => 'not-json{' }] }

      it 'skips the invalid body' do
        expect(articles).to be_empty
      end
    end

    context 'with empty captured_responses' do
      let(:captured_responses) { [] }

      it 'yields nothing' do
        expect(articles).to be_empty
      end
    end

    context 'when the same generic payload is also scraped by JsonDocument' do
      let(:payload) do
        [{ title: 'Shared Headline Extra Words', url: '/shared/one', description: 'Parity check.' }]
      end
      let(:captured_responses) { [{ 'body' => payload.to_json }] }

      it 'yields the same url and title as JsonDocument', :aggregate_failures do
        json_document_articles = Html2rss::AutoSource::Scraper::JsonDocument
                                 .new(payload, url: base_url).each.to_a

        expect(articles).not_to be_empty
        expect(articles.first[:url]).to eq(json_document_articles.first[:url])
        expect(articles.first[:title]).to eq(json_document_articles.first[:title])
      end
    end
  end
end
