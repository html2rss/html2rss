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
  let(:channel_url) { config.dig(:channel, :url) }
  let(:items) { feed.items }
  let(:expected_titles) do
    [
      "Breaking News: ACME Corp's Technology Breakthrough",
      "ACME Corp's Environmental Research Update",
      "ACME Corp's Economic Analysis Report",
      "ACME Corp's Developer Health and Wellness Tips"
    ]
  end

  let(:expected_links) do
    [
      'https://example.com/articles/technology-breakthrough',
      'https://example.com/articles/environmental-research',
      'https://example.com/articles/economic-analysis',
      'https://example.com/articles/health-tips'
    ]
  end

  let(:expected_descriptions) do
    [
      "January 15, 2024 ACME Corp scientists have achieved a major breakthrough in quantum computing technology. This advancement could revolutionize how we process information and solve complex problems. It can finally solve the halting problem... or can it? The research team spent over three years developing this new approach to quantum error correction, which addresses one of the biggest challenges in quantum computing. They also discovered that coffee makes quantum computers work better. Read more",
      "January 14, 2024 New ACME Corp research reveals significant changes in global climate patterns. The study provides important insights into how climate change is affecting different regions around the world. They're trying to make infinite loops carbon-neutral. Researchers analyzed data from over 100 weather stations across five continents to reach these conclusions. The study found that using tabs instead of spaces can reduce your carbon footprint by 0.0001%. Read full article",
      "January 13, 2024 ACME Corp's quarterly economic analysis shows positive trends in several key sectors. The report indicates steady growth in technology and renewable energy industries. The most profitable sector is still selling coffee to developers. Market analysts predict continued expansion in these areas over the next fiscal year. They also predict that the demand for rubber ducks will increase by 42%. View report",
      "January 12, 2024 ACME Corp expert recommendations for maintaining good health during the winter months. These tips can help boost your immune system and overall well-being. Remember: coffee is not a food group, but it is a lifestyle choice. Regular exercise, proper nutrition, and adequate sleep are the three pillars of good health. Also, remember to take breaks from your computer every 2 hours to prevent carpal tunnel syndrome. Read tips"
    ]
  end

  let(:expected_pubdates) do
    [
      'Mon, 15 Jan 2024 10:30:00 +0000',
      'Sun, 14 Jan 2024 14:20:00 +0000',
      'Sat, 13 Jan 2024 09:15:00 +0000',
      'Fri, 12 Jan 2024 08:30:00 +0000'
    ]
  end

  it 'applies the high-signal CSS selector and ignores adverts' do
    expect(items.size).to eq(4)
    expect(items.map(&:title)).to eq(expected_titles)
  end

  it 'converts relative article links to absolute URLs' do
    expect(items.map(&:link)).to eq(expected_links)
  end

  it 'sanitises body copy while keeping the editorial voice intact' do
    expect(items.map(&:description)).to eq(expected_descriptions)
    expect(items.first.description).to include('coffee makes quantum computers work better.')
  end

  it 'parses datetime attributes directly from the markup' do
    expect(items.map { |item| item.pubDate.rfc2822 }).to eq(expected_pubdates)
  end
end
