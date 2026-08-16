# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::XhrArticles do
  let(:base_url) { Html2rss::Url.from_absolute('https://example.com') }
  let(:parsed_body) { Nokogiri::HTML('<html><body></body></html>') }
  let(:article_json) do
    [{ title: 'XHR Headline', url: '/xhr/one', description: 'From a captured fetch.' }].to_json
  end

  describe '.articles?' do
    it 'is never detectable from HTML alone' do
      expect(described_class).not_to be_articles(parsed_body)
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
  end
end
