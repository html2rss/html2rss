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

    context 'when oEmbed link tag uses uppercase MIME type' do
      let(:parsed_body) do
        Nokogiri::HTML(
          '<html><head><link rel="alternate" type="APPLICATION/JSON+OEMBED" href="/oembed.json"></head></html>'
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

  describe '.request_slots' do
    it 'reserves no request slots for any options', :aggregate_failures do
      expect(described_class.request_slots).to eq(0)
      expect(described_class.request_slots(max_requests: 5)).to eq(0)
    end
  end

  describe '#extractable?' do
    subject(:scraper) { described_class.new(parsed_body, url:) }

    context 'when og:title meta tag is present' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><head><meta property="og:title" content="T"></head></html>')
      end

      it { expect(scraper.extractable?).to be true }
    end

    context 'when only an unrelated meta tag is present' do
      let(:parsed_body) { Nokogiri::HTML('<html><head><meta name="description" content="D"></head></html>') }

      it { expect(scraper.extractable?).to be false }
    end
  end

  describe '#each' do
    let(:request_session) { instance_spy(Html2rss::RequestSession) }

    context 'when no block is given' do
      subject(:scraper) { described_class.new(parsed_body, url:) }

      let(:parsed_body) do
        Nokogiri::HTML('<html><head><meta property="og:title" content="T"></head></html>')
      end

      it 'returns an enumerator yielding the same article', :aggregate_failures do
        enumerator = scraper.each
        expect(enumerator).to be_an(Enumerator)
        expect(enumerator.to_a).to eq([{ url: Html2rss::Url.from_absolute(url), title: 'T' }])
      end
    end

    context 'when og:url is relative' do
      subject(:scraper) { described_class.new(parsed_body, url:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:title" content="T"><meta property="og:url" content="/canonical/1"></head></html>
        HTML
      end

      it 'resolves the canonical URL against the page URL' do
        expect(scraper.first[:url]).to eq(Html2rss::Url.from_absolute('https://example.com/canonical/1'))
      end
    end

    context 'when og:url is absent or empty' do
      subject(:scraper) { described_class.new(parsed_body, url:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:title" content="T"><meta property="og:url" content=""></head></html>
        HTML
      end

      it 'falls back to the page URL' do
        expect(scraper.first[:url]).to eq(Html2rss::Url.from_absolute(url))
      end
    end

    context 'when og:title is empty and twitter:title provides the title' do
      subject(:scraper) { described_class.new(parsed_body, url:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:title" content=""><meta name="twitter:title" content="Twitter T"></head></html>
        HTML
      end

      it { expect(scraper.first[:title]).to eq('Twitter T') }
    end

    context 'when og:title and twitter:title both appear' do
      subject(:scraper) { described_class.new(parsed_body, url:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:title" content="First"><meta name="twitter:title" content="Second"></head></html>
        HTML
      end

      it 'keeps the first title declared in the document' do
        expect(scraper.first[:title]).to eq('First')
      end
    end

    context 'when meta tag has a property but no content attribute' do
      subject(:scraper) { described_class.new(parsed_body, url:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:title"><meta property="og:description" content="D"></head></html>
        HTML
      end

      it { expect(scraper.to_a).to be_empty }
    end

    context 'when page has unmapped OpenGraph properties' do
      subject(:scraper) { described_class.new(parsed_body, url:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:site_name" content="Site"><meta property="og:title" content="T"></head></html>
        HTML
      end

      it 'ignores unmapped properties and yields only mapped fields' do
        expect(scraper.to_a).to eq([{ url: Html2rss::Url.from_absolute(url), title: 'T' }])
      end
    end

    context 'when og:title is only declared with a name attribute' do
      subject(:scraper) { described_class.new(parsed_body, url:) }

      let(:parsed_body) do
        Nokogiri::HTML('<html><head><meta name="og:title" content="T"></head></html>')
      end

      it { expect(scraper.to_a).to be_empty }
    end

    context 'when og:description and oEmbed html are both present' do
      subject(:scraper) { described_class.new(parsed_body, url:, request_session:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html>
            <head>
              <meta property="og:title" content="OG Title">
              <meta property="og:description" content="OG Description">
              <meta property="og:image" content="https://example.com/og.jpg">
              <link rel="alternate" type="application/json+oembed" href="https://example.com/oembed.json">
            </head>
          </html>
        HTML
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(
          instance_double(Html2rss::RequestService::Response,
                          parsed_body: { 'title' => 'E', 'html' => '<iframe></iframe>', 'author_name' => 'A' })
        )
      end

      it 'prefers OpenGraph description and keeps oEmbed title and author', :aggregate_failures do
        expect(scraper.first[:description]).to eq('OG Description')
        expect(scraper.first[:title]).to eq('E')
        expect(scraper.first[:author]).to eq('A')
      end
    end

    context 'when oEmbed has no title or author' do
      subject(:scraper) { described_class.new(parsed_body, url:, request_session:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html>
            <head>
              <meta property="og:title" content="OG Title">
              <meta property="article:author" content="Meta Author">
              <link rel="alternate" type="application/json+oembed" href="https://example.com/oembed.json">
            </head>
          </html>
        HTML
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(
          instance_double(Html2rss::RequestService::Response,
                          parsed_body: { 'thumbnail_url' => 'https://example.com/t.jpg' })
        )
      end

      it 'falls back to OpenGraph title and article author', :aggregate_failures do
        expect(scraper.first[:title]).to eq('OG Title')
        expect(scraper.first[:author]).to eq('Meta Author')
        expect(scraper.first[:image]).to eq('https://example.com/t.jpg')
      end
    end

    context 'when oEmbed thumbnail_url and photo url are both present' do
      subject(:scraper) { described_class.new(parsed_body, url:, request_session:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:title" content="T"><link rel="alternate" type="application/json+oembed" href="https://example.com/oembed.json"></head></html>
        HTML
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(
          instance_double(Html2rss::RequestService::Response,
                          parsed_body: { 'type' => 'photo', 'thumbnail_url' => 'https://example.com/thumb.jpg',
                                         'url' => 'https://example.com/photo.jpg' })
        )
      end

      it { expect(scraper.first[:image]).to eq('https://example.com/thumb.jpg') }
    end

    context 'when oEmbed type is not photo' do
      subject(:scraper) { described_class.new(parsed_body, url:, request_session:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:title" content="T"><meta property="og:image" content="https://example.com/og.jpg"><link rel="alternate" type="application/json+oembed" href="https://example.com/oembed.json"></head></html>
        HTML
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(
          instance_double(Html2rss::RequestService::Response,
                          parsed_body: { 'type' => 'video', 'url' => 'https://example.com/video' })
        )
      end

      it 'ignores the url field and keeps the OpenGraph image' do
        expect(scraper.first[:image]).to eq('https://example.com/og.jpg')
      end
    end

    context 'when request_session is missing' do
      subject(:scraper) { described_class.new(parsed_body, url:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:title" content="OG"><link rel="alternate" type="application/json+oembed" href="/oembed.json"></head></html>
        HTML
      end

      it 'keeps OpenGraph data only' do
        expect(scraper.first).to eq({ url: Html2rss::Url.from_absolute(url), title: 'OG' })
      end
    end

    context 'when oEmbed link has an empty href' do
      subject(:scraper) { described_class.new(parsed_body, url:, request_session:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:title" content="OG"><link rel="alternate" type="application/json+oembed" href=""></head></html>
        HTML
      end

      it 'does not issue a follow-up request' do
        scraper.to_a
        expect(request_session).not_to have_received(:follow_up)
      end
    end

    context 'when the page declares more than one oEmbed link' do
      subject(:scraper) { described_class.new(parsed_body, url:, request_session:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html>
            <head>
              <meta property="og:title" content="OG">
              <link rel="alternate" type="application/json+oembed" href="/first.json">
              <link rel="alternate" type="application/json+oembed" href="/second.json">
            </head>
          </html>
        HTML
      end

      it 'fetches the first oEmbed descriptor' do
        allow(request_session).to receive(:follow_up).and_return(nil)
        scraper.to_a
        expect(request_session).to have_received(:follow_up)
          .with(url: Html2rss::Url.from_absolute('https://example.com/first.json'),
                relation: :auto_source, origin_url: Html2rss::Url.from_absolute(url))
      end
    end

    context 'when oEmbed request returns no response' do
      subject(:scraper) { described_class.new(parsed_body, url:, request_session:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:title" content="OG"><link rel="alternate" type="application/json+oembed" href="/oembed.json"></head></html>
        HTML
      end

      before { allow(request_session).to receive(:follow_up).and_return(nil) }

      it { expect(scraper.first).to eq({ url: Html2rss::Url.from_absolute(url), title: 'OG' }) }
    end

    context 'when oEmbed payload is not a JSON object' do
      subject(:scraper) { described_class.new(parsed_body, url:, request_session:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:title" content="OG"><link rel="alternate" type="application/json+oembed" href="/oembed.json"></head></html>
        HTML
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(
          instance_double(Html2rss::RequestService::Response, parsed_body: %w[not an object])
        )
      end

      it { expect(scraper.first).to eq({ url: Html2rss::Url.from_absolute(url), title: 'OG' }) }
    end

    context 'when oEmbed fetch fails' do
      subject(:scraper) { described_class.new(parsed_body, url:, request_session:) }

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><head><meta property="og:title" content="OG Title"><link rel="alternate" type="application/json+oembed" href="https://example.com/oembed.json"></head></html>
        HTML
      end

      before do
        allow(Html2rss::Log).to receive(:warn)
        allow(request_session).to receive(:follow_up).and_raise(Html2rss::Error, 'Network error')
        scraper.to_a
      end

      it 'logs a structured warning describing the failed fetch', :aggregate_failures do
        expect(Html2rss::Log).to have_received(:warn) do |payload|
          event = JSON.parse(payload)
          expect(event).to include('event_name' => 'meta_oembed.fetch_failed', 'host' => 'example.com')
          expect(event['message']).to include('Html2rss::AutoSource::Scraper::MetaOembed', 'Network error')
        end
      end
    end

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
              <meta name="twitter:description" content="Twitter Description">
              <meta name="twitter:image" content="https://example.com/twitter-card.jpg">
            </head>
          </html>
        HTML
      end

      it 'uses twitter image and description tags when og:image/og:description are absent', :aggregate_failures do
        expect(scraper.first[:image]).to eq('https://example.com/twitter-card.jpg')
        expect(scraper.first[:description]).to eq('Twitter Description')
      end
    end

    context 'when page has oEmbed photo type descriptor link and request_session is present' do
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
            'type' => 'photo',
            'title' => 'oEmbed Photo Title',
            'url' => 'https://example.com/photo.jpg'
          }
        )
      end

      before do
        allow(request_session).to receive(:follow_up).and_return(oembed_response)
      end

      it 'uses oEmbed photo url as image when thumbnail_url is missing' do
        expect(scraper.first[:image]).to eq('https://example.com/photo.jpg')
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

    {
      'og:video with type' => ['<meta property="og:video" content="/v/a.mp4">' \
                               '<meta property="og:video:type" content="video/mp4">',
                               [{ url: 'https://example.com/v/a.mp4', type: 'video/mp4' }]],
      'og:audio without type' => ['<meta property="og:audio" content="https://cdn.example.com/a.mp3">',
                                  [{ url: 'https://cdn.example.com/a.mp3', type: nil }]],
      'og:video page embed' => ['<meta property="og:video" content="https://e.com/embed">' \
                                '<meta property="og:video:type" content="text/html">',
                                nil],
      'none' => ['', nil]
    }.each do |name, (markup, expected)|
      context "with media meta tags: #{name}" do
        subject(:article) { described_class.new(parsed_body, url:).each.first }

        let(:parsed_body) { Nokogiri::HTML(%(<html><head><meta property="og:title" content="T">#{markup}</head></html>)) }

        it 'maps to enclosures' do
          actual = article[:enclosures]&.map { |enc| { url: enc[:url].to_s, type: enc[:type] } }
          expect(actual).to eq(expected)
        end
      end
    end
  end
end
