# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Unreliable Site Configuration' do
  subject(:feed) do
    mock_request_service_with_html_fixture('unreliable_site', 'https://example.com')
    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples unreliable_site.yml]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }
  let(:channel_url) { config.dig(:channel, :url) }
  let(:items) { feed.items }
  let(:expected_titles) do
    [
      "Breaking News: ACME Corp's Technology Advances",
      'ACME Corp Science Discovery: New Findings',
      'ACME Corp Environmental Impact Report',
      'ACME Corp Economic Analysis: Market Trends',
      'ACME Corp Developer Health and Wellness Update'
    ]
  end

  let(:expected_links) do
    [
      'https://example.com/articles/breaking-news-technology-advances',
      'https://example.com/articles/science-discovery-new-findings',
      'https://example.com/articles/environmental-impact-report',
      'https://example.com/articles/economic-analysis-market-trends',
      'https://example.com/articles/health-wellness-update'
    ]
  end

  let(:expected_descriptions) do
    [
      "This is a comprehensive article about ACME Corp's latest technology advances. It contains detailed information about various technological breakthroughs that are shaping our future. The content includes multiple paragraphs with rich information that should be properly extracted and processed by the RSS feed generator. Warning: May contain traces of bugs. Additional content that provides more context and depth to the story. This paragraph contains more detailed information that will be sanitized",
      "ACME Corp scientists have made groundbreaking discoveries in the field of quantum physics. This research could revolutionize our understanding of the universe and lead to new technological applications. They discovered that quantum computers work better with coffee. The study involved multiple experiments and data analysis over several years. Researchers from various institutions collaborated to achieve these remarkable results. The most important finding: infinite loops are actually finite in q",
      "A comprehensive report on environmental changes and their impact on global ecosystems. This report covers various aspects of climate change and environmental degradation. ACME Corp is trying to make infinite loops carbon-neutral. The findings suggest that immediate action is required to address these environmental challenges. Various stakeholders need to work together to implement effective solutions. They recommend using tabs instead of spaces to save trees. Long-term strategies and short-term",
      "An in-depth analysis of current market trends and their implications for investors and businesses. This analysis covers various sectors and provides insights into future market movements. Spoiler: coffee stocks are up 42%. An in-depth analysis of current market trends and their implications for investors and businesses. This analysis covers various sectors and provides insights into future market movements. Spoiler: coffee stocks are up 42%. ACME Corp market analysts have identified several key",
      "Latest updates on health and wellness trends that are gaining popularity among developers. These trends include new dietary approaches (coffee is still a food group), exercise routines (typing faster), and mental health practices (rubber duck debugging).ACME Corp experts recommend consulting with healthcare professionals before making significant changes to your lifestyle. It's important to find approaches that work for your individual needs and circumstances. Remember: standing desks are great,"
    ]
  end

  it 'emits channel metadata suitable for flaky upstream sources' do
    expect(feed.channel.ttl).to eq(60)
  end

  it 'extracts resilient titles across heterogeneous markup' do
    expect(items.map(&:title)).to eq(expected_titles)
  end

  it 'sanitises and truncates body content to keep feeds lightweight' do
    expect(items.map(&:description)).to eq(expected_descriptions)
    expect(items.map { |item| item.description.length }).to all(be <= 500)
  end

  it 'normalises every hyperlink via parse_uri post-processing' do
    expect(items.map(&:link)).to eq(expected_links)
  end
end
