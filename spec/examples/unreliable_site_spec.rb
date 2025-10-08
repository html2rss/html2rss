# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Unreliable Site Configuration' do
  subject(:feed) do
    mock_request_service_with_html_fixture('unreliable_site', 'https://example.com')
    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples unreliable_site.yml]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }
  let(:items) { feed.items }

  let(:expected_items) do
    [
      {
        title: "Breaking News: ACME Corp's Technology Advances",
        link: 'https://example.com/articles/breaking-news-technology-advances',
        description_includes: [
          'latest technology advances',
          'Warning: May contain traces of bugs.'
        ]
      },
      {
        title: 'ACME Corp Science Discovery: New Findings',
        link: 'https://example.com/articles/science-discovery-new-findings',
        description_includes: [
          'groundbreaking discoveries in the field of quantum physics',
          'They discovered that quantum computers work better with coffee.'
        ]
      },
      {
        title: 'ACME Corp Environmental Impact Report',
        link: 'https://example.com/articles/environmental-impact-report',
        description_includes: [
          'environmental changes and their impact on global ecosystems',
          'ACME Corp is trying to make infinite loops carbon-neutral.'
        ]
      },
      {
        title: 'ACME Corp Economic Analysis: Market Trends',
        link: 'https://example.com/articles/economic-analysis-market-trends',
        description_includes: [
          'current market trends and their implications',
          'coffee stocks are up 42%'
        ]
      },
      {
        title: 'ACME Corp Developer Health and Wellness Update',
        link: 'https://example.com/articles/health-wellness-update',
        description_includes: [
          'health and wellness trends that are gaining popularity among developers',
          'standing desks are great'
        ]
      }
    ]
  end

  it 'emits channel metadata suitable for flaky upstream sources' do
    expect(feed.channel.ttl).to eq(60)
  end

  it 'extracts resilient titles across heterogeneous markup' do
    expect_feed_items(items, expected_items)
  end

  it 'sanitises and truncates body content to keep feeds lightweight' do
    expect(items.map { |item| item.description.length }).to all(be <= 500)
  end

  it 'normalises every hyperlink via parse_uri post-processing' do
    expect(items.map(&:link)).to eq(expected_items.map { |item| item[:link] })
  end
end
