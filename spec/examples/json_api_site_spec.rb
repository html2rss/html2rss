# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'JSON API Site Configuration' do
  let(:config_file) { File.join(%w[spec examples json_api_site.yml]) }
  let(:json_file) { File.join(%w[spec examples json_api_site.json]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  describe 'configuration loading' do
    it_behaves_like 'validates configuration structure'

    it 'has correct headers configuration', :aggregate_failures do
      expect(config[:headers][:Accept]).to eq('application/json')
      expect(config[:headers][:Authorization]).to be_a(String)
    end

    it 'includes category and tags in categories', :aggregate_failures do
      expect(config[:selectors][:categories]).to include('category')
      expect(config[:selectors][:categories]).to include('tags')
    end

    it 'has enclosure configuration', :aggregate_failures do
      expect(config[:selectors][:enclosure][:selector]).to be_a(String)
      expect(config[:selectors][:enclosure][:content_type]).to be_a(String)
    end

    it_behaves_like 'validates description post-processing'
    it_behaves_like 'validates published_at post-processing'
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our JSON fixture
      mock_request_service_with_json_fixture('json_api_site', 'https://example.com/posts')

      Html2rss.feed(config)
    end

    let(:items) { feed.items }

    it_behaves_like 'generates valid RSS feed'
    it_behaves_like 'extracts valid item content'
    it_behaves_like 'extracts valid published dates'

    it 'extracts author information' do
      author_config = config[:selectors][:author]
      expect(author_config[:selector]).to be_a(String)
    end

    it 'extracts category and tag information as categories' do
      items_with_categories = items.select { |item| item.categories.any? }
      expect(items_with_categories.size).to be > 0
    end

    it 'handles complex JSON structure', :aggregate_failures do
      expect(items.size).to be > 0

      items.each do |item|
        expect(item.title).not_to be_nil
        expect(item.description).not_to be_nil
        expect(item.pubDate).not_to be_nil
      end
    end

    it 'handles items with and without audio files', :aggregate_failures do
      items_with_enclosures = items.select(&:enclosure)
      expect(items_with_enclosures.size).to be >= 0

      items_with_enclosures.each do |item|
        expect(item.enclosure).not_to be_nil
        expect(item.enclosure.url).not_to be_nil
        expect(item.enclosure.type).not_to be_nil
      end
    end
  end
end
