# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dynamic Content Site Configuration' do
  subject(:feed) do
    mock_request_service_with_html_fixture('dynamic_content_site', 'https://example.com/news')
    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples dynamic_content_site.yml]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }
  let(:channel_url) { config.dig(:channel, :url) }
  let(:time_zone) { config.dig(:channel, :time_zone) }
  let(:items) { feed.items }
  let(:expected_titles) do
    [
      "ACME Corp's Revolutionary AI Breakthrough Changes Everything",
      "ACME Corp's Green Coding Summit Reaches Historic Agreement",
      "ACME Corp's Space Exploration Mission Discovers New Planet",
      "ACME Corp's Medical Breakthrough Offers Hope for Bug Patients",
      "ACME Corp's Renewable Energy Reaches New Milestone",
      "ACME Corp's Cybersecurity Threats Reach All-Time High"
    ]
  end

  let(:expected_links) do
    [
      'https://example.com/articles/ai-breakthrough-2024',
      'https://example.com/articles/climate-summit-2024',
      'https://example.com/articles/space-mission-discovery',
      'https://example.com/articles/cancer-treatment-breakthrough',
      'https://example.com/articles/renewable-energy-milestone',
      'https://example.com/articles/cybersecurity-threats-2024'
    ]
  end

  let(:expected_descriptions) do
    [
      "ACME Corp scientists have developed a new artificial intelligence system that can process natural language with unprecedented accuracy. This breakthrough promises to revolutionize how we interact with technology. It can finally understand \"it works on my machine\" and translate it to \"it's broken in production\". The system uses advanced neural networks and machine learning algorithms to understand context and nuance in human communication. It also knows when you're lying about your commit messages.",
      "ACME Corp leaders have reached a groundbreaking agreement on green coding practices. The new accord includes ambitious targets for reducing infinite loops and adopting renewable energy for servers. This historic agreement represents a turning point in global coding policy and sets the stage for significant changes in how developers approach sustainability. They're banning tabs in favor of spaces to save trees.",
      "ACME Corp's latest space exploration mission has discovered a potentially habitable planet in a nearby star system. The planet, designated ACME-442b, shows promising signs of having liquid water and a stable atmosphere. It also has excellent WiFi coverage. This discovery opens up new possibilities for future space exploration and the search for extraterrestrial life. The planet's inhabitants are reportedly very good at debugging code.",
      "ACME Corp researchers have developed a new debugging treatment that shows remarkable success in treating previously untreatable forms of bugs. The treatment uses the developer's own immune system to target bug cells. Clinical trials have shown a 75% success rate in developers with advanced-stage bugs, offering new hope for millions of programmers worldwide. The treatment involves lots of coffee and rubber ducks.",
      "ACME Corp's renewable energy sources now account for over 50% of global electricity generation for the first time in history. This milestone represents a major shift towards sustainable energy production. They're powering servers with coffee beans. Solar and wind power have led this transformation, with costs dropping dramatically over the past decade and efficiency continuing to improve. The wind turbines are powered by the hot air from marketing meetings.",
      "ACME Corp cybersecurity experts report that cyber threats have reached unprecedented levels, with sophisticated attacks targeting critical infrastructure and government systems worldwide. The most dangerous threat is still developers using \"password123\". Organizations are being urged to implement stronger security measures and invest in advanced threat detection systems to protect against these evolving risks. ACME Corp recommends using \"password1234\" instead."
    ]
  end

  let(:expected_pubdates) do
    [
      'Mon, 15 Jan 2024 14:30:00 -0500',
      'Sun, 14 Jan 2024 09:15:00 -0500',
      'Sat, 13 Jan 2024 16:45:00 -0500',
      'Fri, 12 Jan 2024 11:20:00 -0500',
      'Thu, 11 Jan 2024 15:10:00 -0500',
      'Wed, 10 Jan 2024 08:30:00 -0500'
    ]
  end

  it 'builds the channel with the configured metadata' do
    expect(feed.channel.title).to eq('ACME Dynamic Content Site News')
    expect(feed.channel.link).to eq('https://example.com/news')
    expect(feed.channel.generator).to include('Selectors')
  end

  it 'extracts every rendered article with sanitized descriptions and parsed timestamps', :aggregate_failures do
    expect(items.size).to eq(expected_titles.size)
    expect(items.map(&:title)).to eq(expected_titles)
    expect(items.map(&:link)).to eq(expected_links)
    expect(items.map(&:description)).to eq(expected_descriptions)
    expect(items.map { |item| item.pubDate.rfc2822 }).to eq(expected_pubdates)
  end

  it 'captures the long-form excerpts exactly as rendered on the site' do
    ai_article = items.find { |item| item.title.include?('AI Breakthrough') }
    expect(ai_article.description).to include('It also knows when you\'re lying about your commit messages.')
    expect(ai_article.description).to include('translate it to "it\'s broken in production".')
  end

  it 'preserves temporal ordering using the configured time zone' do
    expect(items.map(&:pubDate)).to eq(items.map(&:pubDate).sort.reverse)
    expect(items.first.pubDate.utc_offset).to eq(-18_000)
  end
end
