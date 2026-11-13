# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable-next RSpec/DescribeClass
RSpec.describe 'Redirected gzip table page regression', :aggregate_failures do
  let(:config) do
    {
      channel: {
        url: 'https://example.com/en-gb/HT000001',
        language: 'en',
        ttl: 360,
        time_zone: 'UTC'
      },
      selectors: {
        items: { selector: '.table-wrapper table tbody > tr:not(:first-child)' },
        title: { selector: 'a' },
        url: { selector: 'a:first', extractor: 'href' },
        description: { selector: 'td:nth-child(2)' },
        published_at: {
          selector: 'td:nth-child(3)',
          post_process: [{ name: 'parse_time' }]
        }
      }
    }
  end

  around do |example|
    VCR.use_cassette('security_releases_redirect') { example.run }
  end

  it 'keeps extracting items after a 301 to a gzip-encoded table page' do
    feed = Html2rss.feed(config)

    expect(feed.channel.link).to eq('https://example.com/en-gb/security-releases')
    expect(feed.items.count).to be > 100
    expect(feed.items.first.link).to match(%r{\Ahttps://example\.com/en-gb/})
  end
end
