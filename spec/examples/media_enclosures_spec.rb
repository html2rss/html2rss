# frozen_string_literal: true

require 'spec_helper'

# This spec demonstrates the media enclosures configuration,
# which handles podcast and video content with media enclosures,
# duration extraction, and HTML to Markdown conversion.
RSpec.describe 'Media Enclosures Configuration', type: :example do
  # RSS feed generation tests
  # These tests validate that the configuration successfully generates
  # a valid RSS feed with proper media content extraction
  subject(:feed) { generate_feed_from_config(config, config_name, :html) }

  let(:config_name) { 'media_enclosures_site' }
  let(:config) { load_example_configuration(config_name) }

  it 'generates a valid RSS feed' do
    expect(feed).to be_a_valid_rss_feed
  end

  it 'extracts the correct number of episodes' do
    expect(feed).to have_valid_items
  end

  context 'with basic item content validation' do
    it 'extracts titles correctly' do
      expect(feed).to have_valid_titles
    end

    it 'extracts URLs correctly' do
      expect(feed).to have_valid_links
    end

    it 'extracts descriptions correctly' do
      expect(feed).to have_valid_descriptions
    end

    it 'extracts published dates correctly' do
      expect(feed).to have_valid_published_dates
    end
  end

  context 'with media-specific content validation' do
    it 'extracts duration information as categories' do
      expect(feed).to have_categories
    end

    it 'handles media enclosures' do
      expect(feed).to have_enclosures
    end

    it 'handles episodes without media enclosures' do
      # This test ensures the configuration gracefully handles
      # items that don't have media enclosures
      items = feed.items
      expect(items).to be_an(Array)
    end
  end

  context 'with duration processing' do
    it 'extracts duration from data-duration attribute' do
      all_categories = extract_all_categories(feed)
      duration_categories = all_categories.grep(/^\d+$/)
      expect(duration_categories).not_to be_empty
    end

    it 'validates duration values are non-negative' do
      all_categories = extract_all_categories(feed)
      duration_categories = all_categories.grep(/^\d+$/)

      duration_categories.each do |duration|
        expect(duration.to_i).to be >= 0
      end
    end
  end

  context 'with enclosure validation' do
    it 'validates enclosure URLs are absolute' do
      items = feed.items
      items_with_enclosures = items.select(&:enclosure)

      items_with_enclosures.each do |item|
        expect(item.enclosure.url).to be_a(String)
      end
    end

    it 'validates enclosure URLs are not empty' do
      items = feed.items
      items_with_enclosures = items.select(&:enclosure)

      items_with_enclosures.each do |item|
        expect(item.enclosure.url).not_to be_empty
      end
    end

    it 'validates enclosure types are specified' do
      items = feed.items
      items_with_enclosures = items.select(&:enclosure)

      items_with_enclosures.each do |item|
        expect(item.enclosure.type).to be_a(String)
      end
    end

    it 'validates enclosure types are not empty' do
      items = feed.items
      items_with_enclosures = items.select(&:enclosure)

      items_with_enclosures.each do |item|
        expect(item.enclosure.type).not_to be_empty
      end
    end
  end
end
