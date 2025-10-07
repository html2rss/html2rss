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
  let(:items) { feed.items }
  let(:expected_articles) do
    [
      { title: 'ACME Corp Releases New Laptop with M3 Chip',
        link: 'https://example.com/articles/acme-laptop-m3-2024' },
      { title: 'ACME Corp Launches New AI Assistant Features',
        link: 'https://example.com/articles/acme-ai-assistant-update' },
      { title: 'ACME Motors Announces New Electric Vehicle Model',
        link: 'https://example.com/articles/acme-new-ev-model-2024' },
      { title: 'ACME Software Updates Operating System Preview',
        link: 'https://example.com/articles/acme-os-preview' },
      { title: 'ACME Reality Introduces New VR Headset',
        link: 'https://example.com/articles/acme-vr-headset-2024' },
      { title: 'ACME Cloud Services Expands Cloud Services',
        link: 'https://example.com/articles/acme-cloud-services-expansion' }
    ]
  end

  it 'generates a valid RSS feed' do
    expect(feed).to be_a_valid_rss_feed
  end

  it 'collects the six expected articles with matching titles and links' do
    aggregate_failures do
      expect(items.size).to eq(expected_articles.size)
      expect(items.map(&:title)).to eq(expected_articles.map { |article| article[:title] })
      expect(items.map(&:link)).to eq(expected_articles.map { |article| article[:link] })
    end
  end

  context 'with templated item metadata' do
    subject(:guid_template) { '%<self>s-%<url>s' }

    it 'keeps the first item description intact' do
      expect(items.first.description)
        .to include("It's so fast, it can compile Hello World in under 0.001 seconds!")
    end

    it 'generates the first item GUID from the template' do
      first_item = items.first
      expected_guid = Zlib.crc32(format(guid_template, self: first_item.title, url: first_item.link)).to_s(36)

      expect(first_item.guid.content).to eq(expected_guid)
    end

    it 'keeps the second item description intact' do
      expect(items[1].description)
        .to include("It can now understand 'it works on my machine' and translate it to 'it's broken in production'.")
    end

    it 'generates the second item GUID from the template' do
      second_item = items[1]
      expected_guid = Zlib.crc32(format(guid_template, self: second_item.title, url: second_item.link)).to_s(36)

      expect(second_item.guid.content).to eq(expected_guid)
    end
  end

  it 'rewrites News categories and exposes tags as discrete categories' do
    first_item_categories = items.first.categories.map(&:content)

    expect(first_item_categories).to eq(
      ['Hardware Breaking News', 'ACME Corp', 'Laptops', 'Processors']
    )
  end
end
