# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Conditional Processing Configuration' do
  subject(:feed) do
    # Mock the request service to return our HTML fixture
    mock_request_service_with_html_fixture('conditional_processing_site', 'https://example.com')

    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples conditional_processing_site.yml]) }
  let(:html_file) { File.join(%w[spec examples conditional_processing_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  let(:items) { feed.items }
  let(:titles) { items.map(&:title) }

  it 'generates a valid RSS feed', :aggregate_failures do
    expect(feed).to be_a(RSS::Rss)
    expect(feed.channel.title).to eq('ACME Conditional Processing Site News')
    expect(feed.channel.link).to eq('https://example.com')
  end

  it 'extracts all 6 items from the HTML fixture', :aggregate_failures do
    expect(feed.items).to be_an(Array)
    expect(feed.items.size).to eq(6)
  end

  it 'extracts titles correctly', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    titles = items.map(&:title)
    expect(titles).to all(be_a(String)).and all(satisfy { |title| !title.strip.empty? })
    expect(titles).to include('Breaking News: ACME Corp\'s New Debugging Tool',
                              'Draft Article: ACME Corp\'s Green Coding Initiative',
                              'Archived Article: ACME Corp\'s Economic Analysis of Bug Fixes',
                              'ACME Corp\'s Developer Health and Wellness Guide',
                              'Pending Article: ACME Corp\'s Annual Code Golf Tournament',
                              'ACME Corp\'s Article Without Status (Status: Unknown)')
  end

  it 'extracts URLs correctly', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    urls = items.map(&:link)
    expect(urls).to all(be_a(String)).and all(satisfy { |url| !url.strip.empty? })
    expect(urls).to include('https://example.com/articles/technology-update',
                            'https://example.com/articles/environmental-research',
                            'https://example.com/articles/economic-analysis',
                            'https://example.com/articles/health-wellness',
                            'https://example.com/articles/sports-update',
                            'https://example.com/articles/no-status')
  end

  it 'extracts published dates correctly', :aggregate_failures do
    items_with_time = items.select(&:pubDate)
    expect(items_with_time.size).to be > 0
    expect(items_with_time).to all(have_attributes(pubDate: be_a(Time)))
  end

  it 'applies template post-processing with status interpolation', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    descriptions = items.map(&:description)
    expect(descriptions).to all(be_a(String)).and all(satisfy { |desc| !desc.strip.empty? })
    expect(items.count { |item| item.description.include?('[Status: Published]') }).to be >= 2
    expect(items.count { |item| item.description.include?('[Status: Draft]') }).to be >= 1
    expect(items.count { |item| item.description.include?('[Status: Archived]') }).to be >= 1
    expect(items.count { |item| item.description.include?('[Status: Pending]') }).to be >= 1
  end

  it 'handles missing status values in template gracefully', :aggregate_failures do
    items = feed.items

    # Find the item without status (should have empty status in template)
    no_status_item = items.find { |item| item.title.include?('Without Status') }
    expect(no_status_item).not_to be_nil

    # The template should handle missing status gracefully
    expect(no_status_item.description).to include('[Status: ]')
  end

  it 'extracts status information as categories', :aggregate_failures do
    items_with_status = items.select { |item| item.categories.any? { |cat| cat.content.is_a?(String) } }
    expect(items_with_status.size).to be >= 5
    status_categories = items.flat_map(&:categories).filter_map(&:content)
    expect(status_categories).to include('Published', 'Draft', 'Archived', 'Pending')
  end

  it 'validates that template post-processing preserves original content', :aggregate_failures do
    items = feed.items
    expect(items).to all(have_attributes(description: be_a(String).and(satisfy { |desc|
      desc.length > 50
    }).and(match(/\[Status: [^\]]*\]/))))
  end

  it 'handles different status values correctly in categories', :aggregate_failures do
    expect(items.count { |item| item.categories.any? { |cat| cat.content == 'Published' } }).to be >= 2
    expect(items.count { |item| item.categories.any? { |cat| cat.content == 'Draft' } }).to be >= 1
    expect(items.count { |item| item.categories.any? { |cat| cat.content == 'Archived' } }).to be >= 1
    expect(items.count { |item| item.categories.any? { |cat| cat.content == 'Pending' } }).to be >= 1
  end
end
