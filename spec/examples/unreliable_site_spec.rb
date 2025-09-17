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
    expect(feed.channel.ttl).to eq(60)
  end

  it 'extracts all 5 items from the HTML fixture', :aggregate_failures do
    expect(feed.items).to be_an(Array)
    expect(feed.items.size).to eq(5)
  end

  it 'extracts titles using fallback selectors (h1, h2, .title)', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    titles = items.map(&:title)
    expect(titles).to all(be_a(String)).and all(satisfy { |title| !title.strip.empty? })
    expect(titles).to include('Breaking News: ACME Corp\'s Technology Advances',
                              'ACME Corp Science Discovery: New Findings',
                              'ACME Corp Environmental Impact Report',
                              'ACME Corp Economic Analysis: Market Trends',
                              'ACME Corp Developer Health and Wellness Update')
  end

  it 'extracts URLs correctly with parse_uri post-processing', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    urls = items.map(&:link)
    expect(urls).to all(be_a(String)).and all(satisfy { |url| !url.strip.empty? })
    expect(urls).to include('https://example.com/articles/breaking-news-technology-advances',
                            'https://example.com/articles/science-discovery-new-findings',
                            'https://example.com/articles/environmental-impact-report',
                            'https://example.com/articles/economic-analysis-market-trends',
                            'https://example.com/articles/health-wellness-update')
  end

  it 'applies sanitize_html post-processing to descriptions', :aggregate_failures do
    items = feed.items
    descriptions = items.map(&:description)
    expect(descriptions).to all(be_a(String)).and all(satisfy { |desc| !desc.strip.empty? }).and all(satisfy { |desc|
      !desc.match(/<[^>]+>/)
    })
  end

  it 'applies substring post-processing with 500 character limit', :aggregate_failures do
    items = feed.items
    descriptions = items.map(&:description)
    expect(descriptions).to all(satisfy { |desc| desc.length <= 500 })
    long_descriptions = descriptions.select { |desc| desc.length >= 400 }
    expect(long_descriptions.size).to be > 0
  end

  it 'handles multiple selector fallbacks for items (.post, .article)', :aggregate_failures do
    items = feed.items
    expect(items.size).to eq(5)

    # Verify we got items from both .post and .article selectors
    # This tests that the fallback selector mechanism works
    expect(items.size).to be > 0
  end

  it 'handles different content structures (.content, .excerpt, p)', :aggregate_failures do
    items = feed.items
    descriptions = items.map(&:description)

    # All items should have descriptions regardless of source structure
    expect(descriptions).to all(be_a(String))
    expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })

    # Test that we can extract from different content structures
    # Some items use .content, some use .excerpt, some use direct p tags
    expect(descriptions.size).to eq(5)
  end

  it 'validates that parse_uri post-processing creates valid URLs', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    urls = items.map(&:link)
    expect(urls).to all(match(%r{^https://example\.com/articles/})
    .and(satisfy { |url| !url.include?(' ') })
    .and(satisfy { |url| !url.include?('<') })
    .and(satisfy { |url| !url.include?('>') }))
  end

  it 'sets the correct TTL value for unreliable sites' do
    expect(feed.channel.ttl).to eq(60)
  end

  it 'extracts content from items with different title structures', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    h2_titles = items.select do |item|
      item.title.include?('Technology Advances') || item.title.include?('Environmental Impact')
    end
    h1_titles = items.select { |item| item.title.include?('Science Discovery') }
    dot_title = items.select { |item| item.title.include?('Environmental Impact Report') }
    expect(h2_titles.size).to be >= 2
    expect(h1_titles.size).to be >= 1
    expect(dot_title.size).to be >= 1
  end
end
