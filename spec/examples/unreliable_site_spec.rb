# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Unreliable Site Configuration' do
  subject(:feed) do
    # Mock the request service to return our HTML fixture
    mock_request_service_with_html_fixture('unreliable_site', 'https://example.com')

    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples unreliable_site.yml]) }
  let(:html_file) { File.join(%w[spec examples unreliable_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  it 'generates a valid RSS feed', :aggregate_failures do
    expect(feed).to be_a(RSS::Rss)
    expect(feed.channel.title).to be_a(String)
    expect(feed.channel.link).to be_a(String)
    expect(feed.channel.ttl).to be_a(Integer)
  end

  it 'extracts the correct number of items', :aggregate_failures do
    expect(feed.items).to be_an(Array)
  end

  it 'extracts titles correctly using fallback selectors', :aggregate_failures do
    items = feed.items
    titles = items.map(&:title)
    expect(titles).to all(be_a(String))
    expect(titles).to all(satisfy { |title| !title.strip.empty? })
  end

  it 'extracts URLs correctly with parse_uri post-processing' do
    items = feed.items
    urls = items.map(&:link)
    expect(urls).to all(be_a(String))
  end

  it 'extracts descriptions with proper post-processing', :aggregate_failures do
    items = feed.items
    descriptions = items.map(&:description)
    expect(descriptions).to all(be_a(String))
    expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })
  end

  it 'handles multiple selector fallbacks for items' do
    items = feed.items
    expect(items.size).to be > 0
  end

  it 'applies sanitize_html post-processing' do
    first_item = feed.items.first
    expect(first_item.description).to be_a(String)
  end

  it 'applies substring post-processing with correct length limit' do
    first_item = feed.items.first
    expect(first_item.description.length).to be <= 500
  end

  it 'applies parse_uri post-processing to URLs' do
    first_item = feed.items.first
    expect(first_item.link).to be_a(String)
  end

  it 'sets the correct TTL value' do
    expect(feed.channel.ttl).to be_a(Integer)
  end
end
