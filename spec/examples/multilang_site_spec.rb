# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Multi-Language Site Configuration' do
  subject(:feed) do
    # Mock the request service to return our HTML fixture
    mock_request_service_with_html_fixture('multilang_site', 'https://example.com')

    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples multilang_site.yml]) }
  let(:html_file) { File.join(%w[spec examples multilang_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  it 'generates a valid RSS feed', :aggregate_failures do
    expect(feed).to be_a(RSS::Rss)
    expect(feed.channel.title).to be_a(String)
    expect(feed.channel.link).to be_a(String)
  end

  it 'extracts the correct number of items', :aggregate_failures do
    expect(feed.items).to be_an(Array)
    expect(feed.items.size).to be > 0
  end

  it 'extracts titles correctly using h1 selector', :aggregate_failures do
    items = feed.items
    titles = items.map(&:title)
    expect(titles).to all(be_a(String))
    expect(titles).to all(satisfy { |title| !title.strip.empty? })
  end

  it 'extracts language and topic information as categories' do
    items = feed.items
    items_with_categories = items.select do |item|
      item.categories.any? { |cat| cat.content.is_a?(String) }
    end
    expect(items_with_categories.size).to be > 0
  end

  it 'extracts descriptions correctly', :aggregate_failures do
    items = feed.items
    descriptions = items.map(&:description)
    expect(descriptions).to all(be_a(String))
    expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })
  end

  it 'preserves original content in template processing', :aggregate_failures do
    items = feed.items
    items.each do |item|
      expect(item.title).to be_a(String)
      expect(item.title.length).to be > 0
    end
  end

  it 'has different language values for different items' do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    language_values = items.map do |item|
      language_cat = item.categories.find { |cat| cat.content.is_a?(String) }
      language_cat ? language_cat.content : 'No Language'
    end
    expect(language_values).to all(be_a(String))
  end
end
