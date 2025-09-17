# frozen_string_literal: true

require 'spec_helper'

# This spec demonstrates the combined scraper sources configuration,
# which uses both auto-source detection and manual selectors to extract
# RSS feed data from HTML content.
RSpec.describe 'Combined Scraper Sources Configuration', type: :example do
  let(:config_name) { 'combined_scraper_sources' }
  let(:config) { load_example_configuration(config_name) }

  # Configuration validation tests
  # These tests ensure the configuration file is properly structured
  # and contains all required fields for the combined approach
  context 'when loading configuration' do
    it 'loads with valid basic structure' do
      expect(validate_configuration_structure(config)).to be true
    end

    it 'has auto_source enabled for combined approach' do
      expect(config[:auto_source]).to eq({})
    end

    it 'has enhance enabled for items' do
      expect(config[:selectors][:items][:enhance]).to be true
    end

    context 'with post-processing configuration' do
      it 'has correct gsub post-processing for category' do
        category_post_process = config[:selectors][:category][:post_process]
        expect(validate_post_process_config(category_post_process, %i[name pattern replacement])).to be true
      end

      it 'has correct template post-processing for custom_guid' do
        custom_guid_post_process = config[:selectors][:custom_guid][:post_process]
        expect(validate_post_process_config(custom_guid_post_process, %i[name string methods])).to be true
      end
    end
  end

  # RSS feed generation tests
  # These tests validate that the configuration successfully generates
  # a valid RSS feed with proper content extraction
  context 'when generating RSS feed' do
    subject(:feed) { generate_feed_from_config(config, config_name, :html) }

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
end
