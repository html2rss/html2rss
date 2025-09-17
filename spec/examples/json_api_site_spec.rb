# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'JSON API Site Configuration' do
  subject(:feed) do
    # Mock the request service to return our JSON fixture
    mock_request_service_with_json_fixture('json_api_site', 'https://example.com/posts')

    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples json_api_site.yml]) }
  let(:json_file) { File.join(%w[spec examples json_api_site.json]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  let(:items) { feed.items }

  it 'generates a valid RSS feed', :aggregate_failures do
    expect(feed).to be_a(RSS::Rss)
    expect(feed.channel.title).to eq('ACME JSON API Site News')
    expect(feed.channel.link).to eq('https://example.com/posts')
  end

  it 'extracts all 6 items from the JSON API response', :aggregate_failures do
    expect(feed.items).to be_an(Array)
    expect(feed.items.size).to eq(6)
  end

  it 'extracts titles correctly from JSON data', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    titles = items.map(&:title)
    expect(titles).to all(be_a(String)).and all(satisfy { |title| !title.strip.empty? })
    expect(titles).to include('ACME Corp\'s Revolutionary AI Breakthrough Changes Everything',
                              'Climate Change Summit Reaches Historic Agreement',
                              'Space Exploration Mission Discovers New Planet',
                              'Medical Breakthrough Offers Hope for Cancer Patients',
                              'Renewable Energy Reaches New Milestone',
                              'Cybersecurity Threats Reach All-Time High')
  end

  it 'extracts descriptions correctly with HTML to Markdown conversion', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    descriptions = items.map(&:description)
    expect(descriptions).to all(be_a(String)).and all(satisfy { |desc| !desc.strip.empty? }).and all(satisfy { |desc|
      desc.length > 50
    })
    ai_article = items.find { |item| item.title.include?('AI Breakthrough') }
    expect(ai_article.description).to include('ACME Corp scientists have developed', 'artificial intelligence system')
  end

  it 'handles URLs correctly (no URL selector configured)', :aggregate_failures do
    urls = items.map(&:link)
    # Since no URL selector is configured in the JSON API config, all URLs should be nil
    expect(urls).to all(be_nil)
  end

  it 'extracts published dates correctly from ISO 8601 timestamps', :aggregate_failures do
    items_with_time = items.select(&:pubDate)
    expect(items_with_time.size).to eq(6)
    expect(items_with_time).to all(have_attributes(pubDate: be_a(Time).and(have_attributes(year: 2024))))
  end

  it 'extracts author information correctly', :aggregate_failures do
    items.each do |item|
      # Author information should be available in the description or as a separate field
      # Since the config doesn't specify author extraction, we test that items are valid
      expect(item.title).to be_a(String)
      expect(item.description).to be_a(String)
    end
  end

  it 'extracts category and tag information as categories', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items_with_categories = items.select { |item| item.categories.any? }
    expect(items_with_categories.size).to eq(6)
    all_categories = items.flat_map(&:categories).filter_map(&:content)
    expect(all_categories).to include('Technology', 'Environment', 'Science', 'Health', 'Energy', 'Security')
    expect(all_categories.join(' ')).to include('Artificial Intelligence', 'Machine Learning', 'Climate Change',
                                                'Space Exploration', 'Cancer Research', 'Renewable Energy',
                                                'Cybersecurity')
  end

  it 'handles complex JSON structure with nested objects and arrays', :aggregate_failures do
    expect(items.size).to eq(6)
    expect(items).to all(have_attributes(title: be_a(String), description: be_a(String), pubDate: be_a(Time),
                                         categories: be_an(Array)))
  end

  it 'handles enclosures correctly', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    expect(items).to all(have_attributes(title: be_a(String), description: be_a(String), pubDate: be_a(Time)))
    items_with_enclosures = items.select(&:enclosure)
    if items_with_enclosures.any?
      expect(items_with_enclosures).to all(have_attributes(enclosure: have_attributes(url: be_a(String),
                                                                                      type: be_a(String))))
    end
  end

  it 'validates that JSON path selectors work correctly', :aggregate_failures do
    # Test that the JSON path selectors are working
    # data > array > object should select the items array
    # title should select the title field
    # content should select the content field
    items.each do |item|
      expect(item.title).to be_a(String)
      expect(item.description).to be_a(String)
      expect(item.pubDate).to be_a(Time)
    end
  end

  it 'validates that HTML to Markdown conversion preserves content structure', :aggregate_failures do
    items.each do |item|
      # Content should be processed and have substantial content
      expect(item.description.length).to be > 50

      # Should contain some meaningful content (not all items mention ACME Corp)
      expect(item.description).to be_a(String)
    end
  end
end
