# frozen_string_literal: true

require 'spec_helper'
require 'time'

RSpec.describe 'Performance-Optimized Configuration' do
  subject(:feed) do
    mock_request_service_with_html_fixture('performance_optimized_site', 'https://example.com')
    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples performance_optimized_site.yml]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }
  let(:items) { feed.items }

  let(:expected_items) do
    [
      {
        title: "Breaking News: ACME Corp's Technology Breakthrough",
        link: 'https://example.com/articles/technology-breakthrough',
        description_includes: [
          'major breakthrough in quantum computing technology',
          'They also discovered that coffee makes quantum computers work better.'
        ],
        pub_date: 'Mon, 15 Jan 2024 10:30:00 +0000'
      },
      {
        title: "ACME Corp's Environmental Research Update",
        link: 'https://example.com/articles/environmental-research',
        description_includes: [
          'climate change is affecting different regions around the world',
          'The study found that using tabs instead of spaces can reduce your carbon footprint'
        ],
        pub_date: 'Sun, 14 Jan 2024 14:20:00 +0000'
      },
      {
        title: "ACME Corp's Economic Analysis Report",
        link: 'https://example.com/articles/economic-analysis',
        description_includes: [
          'quarterly economic analysis shows positive trends',
          'the demand for rubber ducks will increase by 42%'
        ],
        pub_date: 'Sat, 13 Jan 2024 09:15:00 +0000'
      },
      {
        title: "ACME Corp's Developer Health and Wellness Tips",
        link: 'https://example.com/articles/health-tips',
        description_includes: [
          'ACME Corp expert recommendations for maintaining good health during the winter months.',
          'Also, remember to take breaks from your computer every 2 hours'
        ],
        pub_date: 'Fri, 12 Jan 2024 08:30:00 +0000'
      }
    ]
  end

  it 'applies the high-signal CSS selector and ignores adverts' do
    expect(items.size).to eq(4)
    expect(items.map(&:title)).to all(include("ACME Corp"))
  end

  it 'converts relative article links to absolute URLs and preserves editorial tone' do
    expect_feed_items(items, expected_items)
  end

  it 'parses datetime attributes directly from the markup' do
    expect(items.map { |item| item.pubDate.rfc2822 }).to eq(expected_items.map { |expected| expected[:pub_date] })
  end
end
