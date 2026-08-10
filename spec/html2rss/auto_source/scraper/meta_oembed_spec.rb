# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::AutoSource::Scraper::MetaOembed do
  let(:url) { 'https://example.com/posts/article-1' }

  describe '.options_key' do
    it { expect(described_class.options_key).to eq(:meta_oembed) }
  end

  describe '.articles?' do
    context 'when og:title meta tag is present' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><head><meta property="og:title" content="Test Article"></head></html>')
      end

      it { expect(described_class.articles?(parsed_body)).to be true }
    end

    context 'when oEmbed link tag is present' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head><link rel="alternate" type="application/json+oembed" href="/oembed.json"></head></html>'
        )
      end

      it { expect(described_class.articles?(parsed_body)).to be true }
    end

    context 'when neither og:title nor oEmbed link tag is present' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><head><title>Just Title</title></head></html>')
      end

      it { expect(described_class.articles?(parsed_body)).to be false }
    end

    context 'when parsed_body is nil' do
      it { expect(described_class.articles?(nil)).to be false }
    end
  end

  describe '#each' do
    let(:request_session) { instance_double(Html2rss::RequestSession) }

    context 'when page has OpenGraph meta tags' do
      subject(:scraper) { described_class.new(parsed_body, url:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html>
            <head>
              <meta property="og:title" content="OpenGraph Title">
              <meta property="og:url" content="https://example.com/posts/article-1">
              <meta property="og:description" content="OpenGraph Description">
              <meta property="og:image" content="https://example.com/image.jpg">
              <meta property="article:published_time" content="2026-08-10T12:00:00Z">
              <meta property="article:author" content="Jane Doe">
            </head>
          </html>
        HTML
      end

      let(:expected_article) do
        {
          url: Html2rss::Url.from_absolute('https://example.com/posts/article-1'),
          title: 'OpenGraph Title',
          description: 'OpenGraph Description',
          author: 'Jane Doe',
          published_at: '2026-08-10T12:00:00Z',
          image: 'https://example.com/image.jpg'
        }
      end

      it 'yields normalized article hash extracted from OpenGraph tags' do
        expect(scraper.to_a).to eq([expected_article])
      end
    end

    context 'when page has twitter tags fallback' do
      subject(:scraper) { described_class.new(parsed_body, url:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html>
            <head>
              <meta property="og:title" content="OG Title">
              <meta name="twitter:image" content="https://example.com/twitter-card.jpg">
            </head>
          </html>
        HTML
      end

      it 'uses twitter image tag when og:image is absent' do
        expect(scraper.first[:image]).to eq('https://example.com/twitter-card.jpg')
      end
    end

    context 'when page has oEmbed descriptor link and request_session is present' do
      subject(:scraper) { described_class.new(parsed_body, url:, request_session:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html>
            <head>
              <meta property="og:title" content="OG Title">
              <link rel="alternate" type="application/json+oembed" href="https://example.com/oembed.json">
            </head>
          </html>
        HTML
      end

      let(:oembed_response) do
        instance_double(
          Html2rss::RequestService::Response,
          parsed_body: {
            'title' => 'oEmbed Title',
            'author_name' => 'oEmbed Author',
            'thumbnail_url' => 'https://example.com/thumb.jpg',
            'html' => '<iframe></iframe>'
          }
        )
      end

      let(:expected_article) do
        {
          url: Html2rss::Url.from_absolute(url),
          title: 'oEmbed Title',
          description: '<iframe></iframe>',
          author: 'oEmbed Author',
          image: 'https://example.com/thumb.jpg'
        }
      end

      before do
        allow(request_session).to receive(:follow_up).with(
          url: Html2rss::Url.from_absolute('https://example.com/oembed.json'),
          relation: :auto_source,
          origin_url: Html2rss::Url.from_absolute(url)
        ).and_return(oembed_response)
      end

      it 'fetches oEmbed JSON and overrides/enriches article fields', :aggregate_failures do
        expect(scraper.first).to eq(expected_article)
      end
    end

    context 'when fetching oEmbed JSON fails' do
      subject(:scraper) { described_class.new(parsed_body, url:, request_session:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html>
            <head>
              <meta property="og:title" content="OG Title">
              <link rel="alternate" type="application/json+oembed" href="https://example.com/oembed.json">
            </head>
          </html>
        HTML
      end

      before do
        allow(request_session).to receive(:follow_up).and_raise(Html2rss::Error, 'Network error')
      end

      it 'gracefully falls back to OpenGraph meta tags' do
        expect(scraper.first[:title]).to eq('OG Title')
      end
    end

    context 'when title is completely missing' do
      subject(:scraper) { described_class.new(parsed_body, url:) }

      let(:parsed_body) do
        Nokogiri::HTML('<html><head><meta property="og:description" content="No title"></head></html>')
      end

      it 'yields nothing' do
        expect(scraper.to_a).to be_empty
      end
    end
  end
end
