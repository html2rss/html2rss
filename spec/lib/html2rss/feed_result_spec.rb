# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedResult do
  subject(:result) do
    described_class.new(channel:, articles:, status:, stylesheets: [{ href: 'rss.xsl', type: 'text/xsl' }])
  end

  let(:channel) do
    Html2rss::Channel.new(
      title: 'Example',
      url: Html2rss::Url.from_absolute('https://example.com'),
      description: 'Example feed',
      language: 'en',
      ttl: 60,
      last_build_date: Time.utc(2024, 1, 1),
      image: nil,
      author: nil
    )
  end
  let(:articles) do
    [
      Html2rss::Article.new(
        id: '1',
        title: 'Hello',
        url: 'https://example.com/hello',
        description: 'Body',
        scraper: Html2rss::Selectors
      )
    ]
  end
  let(:status) { Html2rss::Status.build(articles:, dedup_dropped: 1) }

  describe 'public API surface' do
    it 'exposes only the frozen closed query/render set and never Channel/Articles',
       :aggregate_failures do
      expect(result).to respond_to(:empty?, :channel_title, :to_rss, :to_json_feed, :status)
      expect(result).not_to respond_to(:articles)
      expect(result).not_to respond_to(:channel)
      expect(result.public_methods(false)).not_to include(:articles, :channel)
      expect(result.instance_variables).to include(:@channel, :@articles)
    end
  end

  describe '#empty?' do
    it 'is false when articles are present' do
      expect(result).not_to be_empty
    end

    it 'is true when no articles were extracted' do
      empty = described_class.new(channel:, articles: [], status: Html2rss::Status.build(articles: []))
      expect(empty).to be_empty
    end
  end

  describe '#channel_title' do
    it 'returns the channel title string without exposing channel' do
      expect(result.channel_title).to eq('Example')
    end

    # rubocop:disable RSpec/ExampleLength -- empty Channel fixture + empty?/title contract
    it 'preserves page title when the scrape produced no items', :aggregate_failures do
      empty_channel = Html2rss::Channel.new(
        title: 'Page Title From Head',
        url: Html2rss::Url.from_absolute('https://example.com/empty'),
        description: 'Latest items from https://example.com/empty',
        language: 'en',
        ttl: 60,
        last_build_date: Time.utc(2024, 1, 1),
        image: nil,
        author: nil
      )
      empty = described_class.new(
        channel: empty_channel,
        articles: [],
        status: Html2rss::Status.build(articles: [])
      )

      expect(empty).to be_empty
      expect(empty.channel_title).to eq('Page Title From Head')
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '#to_rss' do
    it 'renders RSS using status generator comment' do
      xml = Nokogiri.XML(result.to_rss.to_s)
      expect(xml.at_css('channel > generator').text).to eq(status.to_generator_comment)
    end
  end

  describe '#to_json_feed' do
    # rubocop:disable RSpec/ExampleLength -- asserts feed_url, user_comment, and content_text routing together
    it 'wires feed_url and status user_comment into the JSON Feed hash', :aggregate_failures do
      payload = result.to_json_feed(feed_url: 'https://example.com/feed.json')

      expect(payload).to include(
        version: Html2rss::FeedBuilder::JsonFeed::VERSION_URL,
        title: 'Example',
        feed_url: 'https://example.com/feed.json',
        user_comment: status.to_generator_comment
      )
      expect(payload[:items].size).to eq(1)
      expect(payload[:items].first[:content_text]).to eq('Body')
      expect(payload[:items].first).not_to have_key(:content_html)
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength -- builds article with image-only DescriptionBuilder path
    it 'routes DescriptionBuilder media to content_html', :aggregate_failures do
      image_article = Html2rss::Article.new(
        id: 'gallery',
        title: 'Gallery',
        url: 'https://example.com/gallery',
        image: 'https://example.com/cover.jpg'
      )
      payload = described_class.new(
        channel:,
        articles: [image_article],
        status: Html2rss::Status.build(articles: [image_article])
      ).to_json_feed

      item = payload[:items].first
      expect(item).to have_key(:content_html)
      expect(item).not_to have_key(:content_text)
      expect(item[:content_html]).to include('<img')
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '#status' do
    it 'exposes frozen telemetry including dedup_dropped', :aggregate_failures do
      expect(result.status.dedup_dropped).to eq(1)
      expect(result.status.scraper_tallies).to eq('Selectors' => 1)
    end
  end

  describe 'Marshal contract' do
    it 'round-trips through Marshal and still renders both formats', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      restored = Marshal.load(Marshal.dump(result))

      expect(restored).to be_a(described_class)
      expect(restored).to be_frozen
      expect(restored).not_to be_empty
      expect(restored.status.to_generator_comment).to eq(status.to_generator_comment)
      expect(restored.to_rss).to be_a(RSS::Rss)
      expect(restored.to_json_feed[:title]).to eq('Example')
    end
  end
end
