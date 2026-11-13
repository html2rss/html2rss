# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::FeedAdvertisement do
  let(:url) { Html2rss::Url.method(:from_absolute) }

  describe '.from_document' do
    subject(:advertisement) { described_class.from_document(Nokogiri::HTML(html), page_url:) }

    let(:page_url) { 'https://example.com/news/' }
    let(:html) do
      <<~HTML
        <html><head>
          <link rel="alternate" type="application/rss+xml" title="Site feed" href="/feed/">
          <link rel="alternate" type="application/rss+xml" title="Show" href="https://feeds.example.net/show.xml">
          <link rel="alternate" type="application/rss+xml" title="Plain" href="http://feeds.example.net/plain.xml">
          <link rel="alternate" type="application/rss+xml" title="Downgraded" href="http://example.com/feed/">
          <link rel="alternate" type="application/rss+xml" title="Again" href="/feed/">
          <link rel="alternate" type="application/json+oembed" href="https://example.net/oembed.json">
          <link rel="alternate" type="application/rss+xml" title="Bad" href="http://exa mple.com/x">
          <link rel="alternate" type="application/rss+xml" title="Script" href="javascript:void(0)">
          <link rel="alternate" type="application/rss+xml" title="Mail" href="mailto:feed@example.com">
        </head><body>
          <link rel="alternate" type="application/rss+xml" href="https://example.net/body.xml">
        </body></html>
      HTML
    end

    it 'records the page URL and freezes its feeds', :aggregate_failures do
      expect(advertisement.page_url).to eq(url[page_url])
      expect(advertisement.feeds).to be_frozen
    end

    it 'maps typed head alternates to titles in document order, upgrading http off the page origin' do
      expect(advertisement.feeds).to eq(
        url['https://example.com/feed/'] => 'Site feed',
        url['https://feeds.example.net/show.xml'] => 'Show',
        url['https://feeds.example.net/plain.xml'] => 'Plain'
      )
    end

    it 'advertises only the listed URLs', :aggregate_failures do
      expect(advertisement.advertises?(url['https://feeds.example.net/show.xml'])).to be(true)
      expect(advertisement.advertises?(url['http://feeds.example.net/plain.xml'])).to be(false)
      expect(advertisement.advertises?(url['https://example.net/body.xml'])).to be(false)
      expect(advertisement.advertises?(url['https://example.net/oembed.json'])).to be(false)
    end

    context 'when an http page advertises a same-origin http feed' do
      let(:page_url) { 'http://example.com/' }
      let(:html) { '<head><link rel="alternate" type="application/rss+xml" href="/feed.xml"></head>' }

      it 'keeps the same-origin http URL' do
        expect(advertisement.feeds.keys).to eq([url['http://example.com/feed.xml']])
      end
    end

    context 'when a page advertises a feed on its host over http on another port' do
      let(:page_url) { 'http://example.com/' }
      let(:html) { '<head><link rel="alternate" type="application/rss+xml" href="http://example.com:8080/f"></head>' }

      it 'upgrades it to https, keeping the port' do
        expect(advertisement.feeds.keys).to eq([url['https://example.com:8080/f']])
      end
    end
  end

  describe 'minting' do
    subject(:advertisement) { described_class.from_document(Nokogiri::HTML(head), page_url: 'https://example.com/') }

    let(:head) { '<head><link rel="alternate" type="application/rss+xml" href="https://feeds.example.net/a.xml"></head>' }
    let(:evil) { url['https://evil.example.net/x.xml'] }

    it 'is closed to constructors', :aggregate_failures do
      expect { described_class.new(page_url: url['https://example.com/'], feeds: {}) }.to raise_error(NoMethodError)
      expect { described_class.allocate }.to raise_error(NoMethodError)
      expect { described_class[url['https://example.com/'], {}] }.to raise_error(NoMethodError)
    end

    it 'has no copy-with-changes path', :aggregate_failures do
      expect(advertisement).not_to respond_to(:with)
      expect(advertisement.dup).to be(advertisement)
      expect(advertisement.clone).to be(advertisement)
      expect(advertisement.clone(freeze: false)).to be(advertisement)
    end

    it 'is frozen with frozen feeds', :aggregate_failures do
      expect(advertisement).to be_frozen
      expect { advertisement.feeds[evil] = 'Evil' }.to raise_error(FrozenError)
      expect(advertisement.advertises?(evil)).to be(false)
    end
  end
end
