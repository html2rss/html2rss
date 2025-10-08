# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'time'

RSpec.describe 'JSON API Site Configuration' do
  subject(:feed) do
    mock_request_service_with_json_fixture('json_api_site', 'https://example.com/posts')
    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples json_api_site.yml]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }
  let(:items) { feed.items }

  let(:expected_items) do
    [
      {
        title: "ACME Corp's Revolutionary AI Breakthrough Changes Everything",
        link: nil,
        description_includes: [
          '<img src="https://example.com/images/ai-breakthrough.jpg"',
          "It can finally understand 'it works on my machine'"
        ],
        categories: ['Technology', 'Artificial Intelligence', 'Machine Learning', 'Innovation'],
        pub_date: 'Mon, 15 Jan 2024 14:30:00 +0000',
        enclosure: { url: 'https://example.com/images/ai-breakthrough.jpg', type: 'image/jpeg', length: 0 }
      },
      {
        title: 'Climate Change Summit Reaches Historic Agreement',
        link: nil,
        description_includes: [
          '<img src="https://example.com/images/climate-summit.jpg"',
          'groundbreaking agreement on climate change mitigation'
        ],
        categories: ['Environment', 'Climate Change', 'Sustainability', 'Policy'],
        pub_date: 'Sun, 14 Jan 2024 09:15:00 +0000',
        enclosure: { url: 'https://example.com/images/climate-summit.jpg', type: 'image/jpeg', length: 0 }
      },
      {
        title: 'Space Exploration Mission Discovers New Planet',
        link: nil,
        description_includes: [
          '<img src="https://example.com/images/space-discovery.jpg"',
          'This discovery opens up new possibilities for future space exploration'
        ],
        categories: ['Science', 'Space Exploration', 'Astronomy', 'Discovery'],
        pub_date: 'Sat, 13 Jan 2024 16:45:00 +0000',
        enclosure: { url: 'https://example.com/images/space-discovery.jpg', type: 'image/jpeg', length: 0 }
      },
      {
        title: 'Medical Breakthrough Offers Hope for Cancer Patients',
        link: nil,
        description_includes: [
          '<img src="https://example.com/images/cancer-research.jpg"',
          'Clinical trials have shown a 75% success rate'
        ],
        categories: ['Health', 'Cancer Research', 'Immunotherapy', 'Medical Breakthrough'],
        pub_date: 'Fri, 12 Jan 2024 11:20:00 +0000',
        enclosure: { url: 'https://example.com/images/cancer-research.jpg', type: 'image/jpeg', length: 0 }
      },
      {
        title: 'Renewable Energy Reaches New Milestone',
        link: nil,
        description_includes: [
          '<img src="https://example.com/images/renewable-energy.jpg"',
          'Solar and wind power have led this transformation'
        ],
        categories: ['Energy', 'Renewable Energy', 'Solar Power', 'Wind Power'],
        pub_date: 'Thu, 11 Jan 2024 15:10:00 +0000',
        enclosure: { url: 'https://example.com/images/renewable-energy.jpg', type: 'image/jpeg', length: 0 }
      },
      {
        title: 'Cybersecurity Threats Reach All-Time High',
        link: nil,
        description_includes: [
          '<img src="https://example.com/images/cybersecurity.jpg"',
          'Organizations are being urged to implement stronger security measures'
        ],
        categories: ['Security', 'Cybersecurity', 'Threat Detection', 'Infrastructure Security'],
        pub_date: 'Wed, 10 Jan 2024 08:30:00 +0000',
        enclosure: { url: 'https://example.com/images/cybersecurity.jpg', type: 'image/jpeg', length: 0 }
      }
    ]
  end

  it 'loads channel metadata from the configuration file', :aggregate_failures do
    expect(feed.channel.title).to eq('ACME JSON API Site News')
    expect(feed.channel.link).to eq('https://example.com/posts')
  end

  it 'materialises feed items directly from the API payload' do
    expect_feed_items(items, expected_items)
  end

  it 'omits item links when no selector is configured' do
    expect(items.map(&:link)).to all(be_nil)
  end
end
