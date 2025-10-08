# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dynamic Content Site Configuration' do
  subject(:feed) do
    mock_request_service_with_html_fixture('dynamic_content_site', 'https://example.com/news')
    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples dynamic_content_site.yml]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }
  let(:items) { feed.items }

  let(:expected_items) do
    [
      {
        title: "ACME Corp's Revolutionary AI Breakthrough Changes Everything",
        link: 'https://example.com/articles/ai-breakthrough-2024',
        description_includes: [
          'It can finally understand "it works on my machine"',
          "It also knows when you're lying about your commit messages."
        ],
        pub_date: 'Mon, 15 Jan 2024 14:30:00 -0500'
      },
      {
        title: "ACME Corp's Green Coding Summit Reaches Historic Agreement",
        link: 'https://example.com/articles/climate-summit-2024',
        description_includes: [
          'green coding practices',
          "They're banning tabs in favor of spaces to save trees."
        ],
        pub_date: 'Sun, 14 Jan 2024 09:15:00 -0500'
      },
      {
        title: "ACME Corp's Space Exploration Mission Discovers New Planet",
        link: 'https://example.com/articles/space-mission-discovery',
        description_includes: [
          'The planet, designated ACME-442b',
          'inhabitants are reportedly very good at debugging code.'
        ],
        pub_date: 'Sat, 13 Jan 2024 16:45:00 -0500'
      },
      {
        title: "ACME Corp's Medical Breakthrough Offers Hope for Bug Patients",
        link: 'https://example.com/articles/cancer-treatment-breakthrough',
        description_includes: [
          'debugging treatment',
          'The treatment involves lots of coffee and rubber ducks.'
        ],
        pub_date: 'Fri, 12 Jan 2024 11:20:00 -0500'
      },
      {
        title: "ACME Corp's Renewable Energy Reaches New Milestone",
        link: 'https://example.com/articles/renewable-energy-milestone',
        description_includes: [
          "They're powering servers with coffee beans.",
          'The wind turbines are powered by the hot air from marketing meetings.'
        ],
        pub_date: 'Thu, 11 Jan 2024 15:10:00 -0500'
      },
      {
        title: "ACME Corp's Cybersecurity Threats Reach All-Time High",
        link: 'https://example.com/articles/cybersecurity-threats-2024',
        description_includes: [
          'The most dangerous threat is still developers using "password123".',
          'ACME Corp recommends using "password1234" instead.'
        ],
        pub_date: 'Wed, 10 Jan 2024 08:30:00 -0500'
      }
    ]
  end

  it 'builds the channel with the configured metadata' do
    expect(feed.channel.title).to eq('ACME Dynamic Content Site News')
    expect(feed.channel.link).to eq('https://example.com/news')
    expect(feed.channel.generator).to include('Selectors')
  end

  it 'extracts every rendered article with sanitized descriptions and parsed timestamps' do
    expect_feed_items(items, expected_items)
  end

  it 'captures the long-form excerpts exactly as rendered on the site' do
    ai_article = items.find { |item| item.title.include?('AI Breakthrough') }
    expect(ai_article.description).to include("It also knows when you're lying about your commit messages.")
    expect(ai_article.description).to include('translate it to "it\'s broken in production".')
  end

  it 'preserves temporal ordering using the configured time zone' do
    expect(items.map(&:pubDate)).to eq(items.map(&:pubDate).sort.reverse)
    expect(items.first.pubDate.utc_offset).to eq(-18_000)
  end
end
