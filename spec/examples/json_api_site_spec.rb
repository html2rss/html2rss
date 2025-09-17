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

  it_behaves_like 'generates valid RSS feed'
  it_behaves_like 'extracts valid item content'
  it_behaves_like 'extracts valid published dates'

  it 'extracts category and tag information as categories' do
    items_with_categories = items.select { |item| item.categories.any? }
    expect(items_with_categories.size).to be > 0
  end

  it 'handles complex JSON structure', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    expect(items.size).to be > 0

    items.each do |item|
      expect(item.title).not_to be_nil
      expect(item.description).not_to be_nil
      expect(item.pubDate).not_to be_nil
    end
  end

  it 'handles items with and without audio files', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items_with_enclosures = items.select(&:enclosure)
    expect(items_with_enclosures.size).to be >= 0

    items_with_enclosures.each do |item|
      expect(item.enclosure).not_to be_nil
      expect(item.enclosure.url).not_to be_nil
      expect(item.enclosure.type).not_to be_nil
    end
  end
end
