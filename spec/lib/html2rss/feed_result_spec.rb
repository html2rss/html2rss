# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::FeedResult do
  subject(:result) do
    described_class.new(channel:, articles:, status:, stylesheets: [{ href: 'rss.xsl', type: 'text/xsl' }])
  end

  let(:channel_response) do
    Html2rss::RequestService::Response.new(
      body: '<html><head><title>Example</title></head></html>',
      url: Html2rss::Url.from_absolute('https://example.com'),
      headers: {
        'content-type' => 'text/html',
        'content-language' => 'en',
        'cache-control' => 'max-age=3600',
        'last-modified' => 'Mon, 01 Jan 2024 00:00:00 GMT'
      }
    )
  end
  let(:channel) do
    Html2rss::Channel.new(
      channel_response,
      overrides: { title: 'Example', description: 'Example feed', language: 'en', ttl: 60 }
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
    it 'exposes exactly the frozen closed query/render set', :aggregate_failures do
      expect(result.public_methods(false)).to match_array(%i[empty? channel_title to_rss to_json_feed status])
      expect(result).not_to respond_to(:articles)
      expect(result).not_to respond_to(:channel)
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

    context 'when the scrape produced no items' do
      let(:page_channel) do
        Html2rss::Channel.new(
          channel_response,
          overrides: { title: 'Page Title From Head', description: 'Example feed' }
        )
      end

      it 'preserves page title', :aggregate_failures do
        empty = described_class.new(channel: page_channel, articles: [],
                                    status: Html2rss::Status.build(articles: []))

        expect(empty).to be_empty
        expect(empty.channel_title).to eq('Page Title From Head')
      end
    end
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
      expect(payload[:items].first[:content_html]).to eq('Body')
      expect(payload[:items].first).not_to have_key(:content_text)
    end
    # rubocop:enable RSpec/ExampleLength
  end

  describe '#status' do
    it 'exposes frozen telemetry including dedup_dropped', :aggregate_failures do
      expect(result.status.dedup_dropped).to eq(1)
      expect(result.status.scraper_tallies).to eq('Selectors' => 1)
      expect(result.status.selected_strategy).to be_nil
      expect(result.status.attempt_count).to eq(0)
      expect(result.status.to_h).not_to include(:selected_strategy, :attempt_count)
    end
  end

  describe 'immutability' do
    # rubocop:disable RSpec/ExampleLength -- defensive copy of articles + stylesheet hashes
    it 'defensively copies articles and stylesheets from the caller', :aggregate_failures do
      articles_input = articles.dup
      styles = [{ href: +'rss.xsl', type: +'text/xsl' }]
      built = described_class.new(channel:, articles: articles_input, status:, stylesheets: styles)

      articles_input << Html2rss::Article.new(id: '2', title: 'Nope', url: 'https://example.com/x')
      styles.first[:href].replace('evil.xsl')

      expect(built).not_to be_empty
      expect(built.to_json_feed[:items].size).to eq(1)
      expect(built.to_rss.to_s).to include('rss.xsl')
      expect(built.to_rss.to_s).not_to include('evil.xsl')
    end
    # rubocop:enable RSpec/ExampleLength

    it 'exposes channel_title for callers without a channel reader', :aggregate_failures do
      expect(result.channel_title).to eq('Example')
      expect(result).not_to respond_to(:channel)
    end
  end

  describe 'Marshal contract' do
    # Full render-after-load lands with materialized Channel/Article (later stack PRs).
    # rubocop:disable RSpec/ExampleLength -- round-trip identity + status telemetry fields
    it 'round-trips FeedResult and Status through Marshal', :aggregate_failures do
      restored = Marshal.load(Marshal.dump(result))

      expect(restored).to be_a(described_class)
      expect(restored).to be_frozen
      expect(restored).not_to be_empty
      expect(restored.channel_title).to eq('Example')
      expect(restored.status.to_generator_comment).to eq(status.to_generator_comment)
      expect(restored.status.selected_strategy).to eq(status.selected_strategy)
      expect(restored.status.attempt_count).to eq(status.attempt_count)
    end
    # rubocop:enable RSpec/ExampleLength
  end
end
