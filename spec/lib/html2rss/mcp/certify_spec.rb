# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::MCP::Certify do
  describe '.check' do
    let(:valid_config) do
      {
        channel: { url: 'https://example.com', title: 'Example' },
        selectors: {
          items: { selector: 'article' },
          title: { selector: 'h2' },
          url: { selector: 'a', extractor: 'href' }
        }
      }
    end

    it 'returns a report with valid: false when schema validation fails', :aggregate_failures do
      report = described_class.check(config: { channel: { url: 'not-a-url' } })

      expect(report.valid).to be(false)
      expect(report.errors).not_to be_nil
      expect(report.live_check).to be_nil
    end

    it 'returns valid: true without live check when check_live_feed is false', :aggregate_failures do
      report = described_class.check(config: valid_config, check_live_feed: false)

      expect(report.valid).to be(true)
      expect(report.errors).to be_nil
      expect(report.live_check).to be_nil
    end

    # rubocop:disable RSpec/ExampleLength
    it 'returns valid: true with live check metrics when items exist', :aggregate_failures do
      rss_item = instance_double(
        RSS::Rss::Channel::Item,
        title: 'Article 1',
        link: 'https://example.com/articles/1'
      )
      rss = instance_double(RSS::Rss, items: [rss_item])
      allow(Html2rss).to receive(:feed_result).and_return(
        instance_double(Html2rss::FeedResult, to_rss: rss, empty?: false)
      )

      report = described_class.check(config: valid_config, check_live_feed: true)

      expect(report.valid).to be(true)
      expect(report.errors).to be_nil
      expect(report.live_check[:item_count]).to eq(1)
      expect(report.live_check[:sample_items]).to eq([{ title: 'Article 1', url: 'https://example.com/articles/1' }])
      expect(report.live_check[:warnings]).to be_empty
    end

    it 'returns valid: false and flags warning when feed produces zero items', :aggregate_failures do
      empty_rss = instance_double(RSS::Rss, items: [])
      allow(Html2rss).to receive(:feed_result).and_return(
        instance_double(Html2rss::FeedResult, to_rss: empty_rss, empty?: true)
      )

      report = described_class.check(config: valid_config, check_live_feed: true)

      expect(report.valid).to be(false)
      expect(report.live_check[:warnings]).to include('Feed produced 0 items')
    end

    it 'flags non-absolute URL warning when item has relative URL', :aggregate_failures do
      relative_item = instance_double(
        RSS::Rss::Channel::Item,
        title: 'Article Rel',
        link: '/relative/path'
      )
      relative_rss = instance_double(RSS::Rss, items: [relative_item])
      allow(Html2rss).to receive(:feed_result).and_return(
        instance_double(Html2rss::FeedResult, to_rss: relative_rss, empty?: false)
      )

      report = described_class.check(config: valid_config, check_live_feed: true)

      expect(report.valid).to be(false)
      expect(report.live_check[:warnings]).to include('Item with non-absolute URL detected: /relative/path')
    end
    # rubocop:enable RSpec/ExampleLength
  end
end
