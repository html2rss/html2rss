# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Html::FeedLink do
  describe '.from_document' do
    subject(:feed_links) { described_class.from_document(document) }

    let(:html) do
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
          <link rel="canonical" href="https://example.com/blog">
          <link rel="alternate" type="application/rss+xml" href="https://example.com/feed.xml" title="RSS">
          <link rel="alternate" type="application/atom+xml; charset=utf-8" href="/atom.xml" title="Atom">
          <link rel="alternate" type="application/json+oembed" href="https://example.com/oembed.json">
          <link rel="alternate" type="application/rss+xml" href="   " title="empty href">
          <link rel="alternate stylesheet" type="text/css" href="/theme.css">
        </head>
        <body>
          <link rel="alternate" type="application/rss+xml" href="https://example.com/body-feed.xml">
          <a href="/feed">Guessed feed path</a>
          <a href="/rss.xml">Guessed rss.xml</a>
        </body>
        </html>
      HTML
    end
    let(:document) { Nokogiri::HTML(html) }

    let(:expected) do
      [
        described_class.new(href: 'https://example.com/feed.xml', mime_type: 'application/rss+xml'),
        described_class.new(href: '/atom.xml', mime_type: 'application/atom+xml')
      ]
    end

    it 'keeps head RSS/Atom alternates and ignores oembed, body links, and /feed guesses' do
      expect(feed_links).to eq(expected)
    end
  end
end
