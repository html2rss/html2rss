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

  describe '.new' do
    let(:channel_subclass) do
      Class.new(Html2rss::Channel).new(
        title: channel.title, url: channel.url, description: channel.description, language: channel.language,
        ttl: channel.ttl, last_build_date: channel.last_build_date, image: channel.image, author: channel.author
      )
    end
    let(:status_subclass) do
      Class.new(Html2rss::Status).new(
        version: status.version, scraper_tallies: status.scraper_tallies, dedup_dropped: status.dedup_dropped
      )
    end

    # rubocop:disable-next RSpec/ExampleLength -- type errors, subclass acceptance, and frozen articles
    it 'rejects a non-Channel, non-Status, or non-Article and freezes stored articles', :aggregate_failures do
      expect { described_class.new(channel: Object.new, articles:, status:) }
        .to raise_error(ArgumentError, 'channel must be a Html2rss::Channel')
      expect { described_class.new(channel:, articles:, status: Object.new) }
        .to raise_error(ArgumentError, 'status must be a Html2rss::Status')
      expect { described_class.new(channel:, articles: [Object.new], status:) }
        .to raise_error(ArgumentError, 'articles must all be Html2rss::Article')

      built = described_class.new(channel: channel_subclass, articles:, status: status_subclass)

      expect(built.channel_title).to eq('Example')
      expect(built.instance_variable_get(:@articles)).to be_frozen
    end

    it 'rejects a non-array articles list or stylesheet list', :aggregate_failures do
      expect { described_class.new(channel:, articles: nil, status:) }
        .to raise_error(ArgumentError, 'articles must be an Array')
      expect { described_class.new(channel:, articles:, status:, stylesheets: nil) }
        .to raise_error(ArgumentError, 'stylesheets must be an Array')
    end

    it 'rejects String lists for articles and stylesheets', :aggregate_failures do
      expect { described_class.new(channel:, articles: 'hello', status:) }
        .to raise_error(ArgumentError, 'articles must be an Array')
      expect { described_class.new(channel:, articles:, status:, stylesheets: 'rss.xsl') }
        .to raise_error(ArgumentError, 'stylesheets must be an Array')
    end

    it 'accepts Array subclasses for articles and stylesheets', :aggregate_failures do
      article_list = Class.new(Array).new(articles)
      sheet_list = Class.new(Array).new([{ href: 'rss.xsl', type: 'text/xsl' }])
      built = described_class.new(channel:, articles: article_list, status:, stylesheets: sheet_list)

      expect(built.empty?).to be(false)
      expect(built.to_rss.to_s).to include('rss.xsl')
    end
  end

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

    it 'preserves page title when the scrape produced no items', :aggregate_failures do
      empty = described_class.new(channel: channel.with(title: 'Page Title From Head'), articles: [],
                                  status: Html2rss::Status.build(articles: []))

      expect(empty).to be_empty
      expect(empty.channel_title).to eq('Page Title From Head')
    end
  end

  describe '#to_rss' do
    it 'renders stylesheets and the status generator comment', :aggregate_failures do
      rss = result.to_rss.to_s
      xml = Nokogiri.XML(rss)
      expect(xml.at_css('channel > generator').text).to eq(status.to_generator_comment)
      expect(rss).to include('rss.xsl')
    end
  end

  describe '#to_json_feed' do
    # rubocop:disable-next RSpec/ExampleLength -- asserts feed_url, user_comment, and content_text routing together
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

    it 'omits feed_url when the caller does not pass one' do
      expect(result.to_json_feed).not_to have_key(:feed_url)
    end
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
    # rubocop:disable-next RSpec/ExampleLength -- defensive copy of articles + stylesheet hashes
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

    # rubocop:disable-next RSpec/ExampleLength -- string keys and caller mutation share one render
    it 'copies string-keyed stylesheet values before rendering', :aggregate_failures do
      href = +'rss.xsl'
      styles = [{ 'href' => href, 'type' => +'text/xsl' }]
      built = described_class.new(channel:, articles:, status:, stylesheets: styles)
      href.replace('evil.xsl')
      rss = built.to_rss.to_s
      expect(rss).to include('rss.xsl')
      expect(rss).not_to include('evil.xsl')
    end

    it 'copies a String subclass stylesheet href' do
      href = Class.new(String).new('rss.xsl')
      built = described_class.new(channel:, articles:, status:, stylesheets: [{ href:, type: 'text/xsl' }])
      href.replace('evil.xsl')
      expect(built.to_rss.to_s).to include('rss.xsl')
    end

    it 'rejects a non-string stylesheet media value' do
      sheet = { href: 'rss.xsl', type: 'text/xsl', media: :all }
      built = described_class.new(channel:, articles:, status:, stylesheets: [sheet])
      expect { built.to_rss }.to raise_error(ArgumentError, 'stylesheet.media must be a String')
    end

    it 'copies stylesheet values from an object that converts to a hash' do
      href = +'rss.xsl'
      sheet = Struct.new(:href, :type).new(href, +'text/xsl')
      built = described_class.new(channel:, articles:, status:, stylesheets: [sheet])
      href.replace('evil.xsl')
      expect(built.to_rss.to_s).to include('rss.xsl')
    end

    it 'freezes the stylesheet list, each sheet, and copied strings', :aggregate_failures do
      built = described_class.new(channel:, articles:, status:, stylesheets: [{ href: +'rss.xsl', type: +'text/xsl' }])
      stored = built.instance_variable_get(:@stylesheets)
      expect(stored).to be_frozen
      expect(stored.first).to be_frozen
      expect(stored.first[:href]).to be_frozen
    end

    it 'keeps a non-string stylesheet value as the same object' do
      extra = Object.new
      built = described_class.new(
        channel:, articles:, status:, stylesheets: [{ href: +'rss.xsl', type: +'text/xsl', extra: }]
      )

      expect(built.instance_variable_get(:@stylesheets).first[:extra]).to equal(extra)
    end

    it 'keeps channel_title immutable for callers', :aggregate_failures do
      expect(result.channel_title).to be_frozen
      expect { result.channel_title << 'X' }.to raise_error(FrozenError)
      expect(result.to_json_feed[:title]).to eq('Example')
    end
  end

  describe 'Marshal contract' do
    # rubocop:disable-next RSpec/ExampleLength -- round-trip identity + both render formats
    it 'round-trips through Marshal and still renders both formats', :aggregate_failures do
      restored = Marshal.load(Marshal.dump(result))

      expect(restored).to be_a(described_class)
      expect(restored).to be_frozen
      expect(restored).not_to be_empty
      expect(restored.status.to_generator_comment).to eq(status.to_generator_comment)
      expect(restored.status.selected_strategy).to eq(status.selected_strategy)
      expect(restored.status.attempt_count).to eq(status.attempt_count)
      expect(restored.to_rss).to be_a(RSS::Rss)
      expect(restored.to_rss.to_s).to include('rss.xsl')
      expect(restored.to_json_feed[:title]).to eq('Example')
    end
  end
end
