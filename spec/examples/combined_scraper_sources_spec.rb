# frozen_string_literal: true

require 'spec_helper'

# This spec demonstrates the combined scraper sources configuration,
# which uses both auto-source detection and manual selectors to extract
# RSS feed data from HTML content.
RSpec.describe 'Combined Scraper Sources Configuration', type: :example do
  # RSS feed generation tests
  # These tests validate that the configuration successfully generates
  # a valid RSS feed with proper content extraction
  subject(:feed) { generate_feed_from_config(config, config_name, :html) }

  let(:config_name) { 'combined_scraper_sources' }
  let(:config) { load_example_configuration(config_name) }

  it 'generates a valid RSS feed' do
    expect(feed).to be_a_valid_rss_feed
  end

  it 'extracts items using combined auto-source and manual selectors' do
    expect(feed).to have_valid_items
  end

  context 'with item content validation' do
    it 'extracts titles correctly' do
      expect(feed).to have_valid_titles
    end

    it 'extracts URLs correctly' do
      expect(feed).to have_valid_links
    end

    it 'extracts descriptions correctly' do
      expect(feed).to have_valid_descriptions
    end

    it 'generates valid GUIDs for items' do
      expect(feed).to have_valid_guids
    end
  end

  context 'with category processing' do
    it 'applies gsub replacement to categories' do
      expect(feed).to have_categories
    end

    it 'extracts tags correctly' do
      all_tags = extract_all_categories(feed)
      expect(all_tags).not_to be_empty
    end
  end
end
