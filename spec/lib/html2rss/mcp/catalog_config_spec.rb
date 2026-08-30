# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::MCP::CatalogConfig do
  describe '.generate' do
    let(:url) { 'https://www.bsi.bund.de/news' }
    let(:capture_result) do
      instance_double(
        Html2rss::Capture::CaptureResult,
        config: {
          channel: { url:, title: 'BSI News', time_zone: 'UTC' },
          selectors: { items: { selector: 'article.news', enhance: true } }
        },
        articles_count: 5,
        channel_title: 'BSI News'
      )
    end

    before do
      allow(Html2rss::Capture).to receive(:build).with(url, strategy: :auto).and_return(capture_result)
      allow(Html2rss::MCP::Inspect).to receive(:call).with(url:, strategy: :auto).and_return(
        { status: 200, alternate_feeds: [{ href: 'https://www.bsi.bund.de/news/feed.xml' }] }
      )
    end

    # rubocop:disable RSpec/ExampleLength
    it 'generates a catalog-ready YAML configuration with extracted domain and native feed detection',
       :aggregate_failures do
      result = described_class.generate(url:, topics: %w[security tech], summary: 'BSI Security News')

      expect(result.domain).to eq('bund.de')
      expect(result.native_feed_detected).to be(true)
      expect(result.alternate_feeds).to eq([{ href: 'https://www.bsi.bund.de/news/feed.xml' }])
      expect(result.articles_count).to eq(5)
      expect(result.suggested_topics).to eq(%w[security tech])

      parsed = Html2rss::Config.from_yaml(result.yaml)
      expect(parsed.dig(:directory, :title)).to eq('BSI News')
      expect(parsed.dig(:directory, :topics)).to eq(%w[security tech])
      expect(parsed.dig(:directory, :summary)).to eq('BSI Security News')
      expect(parsed.dig(:channel, :title)).to eq('BSI News')
      expect(parsed.dig(:selectors, :items, :selector)).to eq('article.news')
    end
    # rubocop:enable RSpec/ExampleLength

    it 'falls back to default topic when topics are not provided', :aggregate_failures do
      result = described_class.generate(url:)

      expect(result.suggested_topics).to eq(['news'])
      parsed = Html2rss::Config.from_yaml(result.yaml)
      expect(parsed.dig(:directory, :topics)).to eq(['news'])
    end

    it 'raises ArgumentError when invalid topics are provided' do
      expect do
        described_class.generate(url:, topics: ['invalid_topic_xyz'])
      end.to raise_error(ArgumentError, /Invalid topic\(s\): invalid_topic_xyz/)
    end
  end
end
