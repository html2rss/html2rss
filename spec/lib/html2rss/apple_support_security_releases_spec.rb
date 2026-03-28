# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Apple support security releases regression', :aggregate_failures do
  let(:config) do
    {
      channel: {
        url: 'https://support.apple.com/en-gb/HT201222',
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
    VCR.use_cassette('apple_support_security_releases') { example.run }
  end

  it 'keeps extracting items after the redirect to the current support article' do
    feed = Html2rss.feed(config)

    expect(feed.channel.link).to eq('https://support.apple.com/en-gb/100100')
    expect(feed.items.count).to be > 100
    expect(feed.items.first.link).to match(%r{\Ahttps://support\.apple\.com/en-gb/})
  end
end
# rubocop:enable RSpec/DescribeClass
