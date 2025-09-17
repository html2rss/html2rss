# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Performance-Optimized Configuration' do
  subject(:feed) do
    # Mock the request service to return our HTML fixture
    mock_request_service_with_html_fixture('performance_optimized_site', 'https://example.com')

    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples performance_optimized_site.yml]) }
  let(:html_file) { File.join(%w[spec examples performance_optimized_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  let(:items) { feed.items }

  it 'generates a valid RSS feed', :aggregate_failures do
    expect(feed).to be_a(RSS::Rss)
    expect(feed.channel.title).to eq('ACME Performance-Optimized Site News')
    expect(feed.channel.link).to eq('https://example.com')
  end

  it 'extracts only the 4 main content items (excludes ads and sidebar)', :aggregate_failures do
    expect(feed.items).to be_an(Array)
    expect(feed.items.size).to eq(4) # Should exclude advertisement and sidebar content
  end

  it 'extracts titles correctly', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    titles = items.map(&:title)
    expect(titles).to all(be_a(String)).and all(satisfy { |title| !title.strip.empty? })
    expect(titles).to include('Breaking News: ACME Corp\'s Technology Breakthrough',
                              'ACME Corp\'s Environmental Research Update',
                              'ACME Corp\'s Economic Analysis Report',
                              'ACME Corp\'s Developer Health and Wellness Tips')
    expect(titles).not_to include('Sponsored Content: Buy ACME Corp\'s Product', 'Sidebar Content', 'Sidebar Article')
  end

  it 'extracts URLs correctly', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    urls = items.map(&:link)
    expect(urls).to all(be_a(String)).and all(satisfy { |url| !url.strip.empty? })
    expect(urls).to include('https://example.com/articles/technology-breakthrough',
                            'https://example.com/articles/environmental-research',
                            'https://example.com/articles/economic-analysis',
                            'https://example.com/articles/health-tips')
    expect(urls).not_to include('https://example.com/ads/product-promotion',
                                'https://example.com/sidebar/article',
                                'https://example.com/sidebar/sidebar-article')
  end

  it 'extracts published dates correctly from time elements', :aggregate_failures do
    items_with_time = items.select(&:pubDate)
    expect(items_with_time.size).to eq(4)
    expect(items_with_time).to all(have_attributes(pubDate: be_a(Time)))
  end

  it 'excludes advertisements using :not(.advertisement) selector', :aggregate_failures do
    items = feed.items
    titles = items.map(&:title)

    # Ensure no advertisement content is included
    expect(titles).not_to include('Sponsored Content: Buy ACME Corp\'s Product')

    # Verify we still have the expected number of items
    expect(items.size).to eq(4)
  end

  it 'excludes sidebar content by limiting to .main-content', :aggregate_failures do
    items = feed.items
    titles = items.map(&:title)

    # Ensure no sidebar content is included
    expect(titles).not_to include('Sidebar Content')
    expect(titles).not_to include('Sidebar Article')

    # Verify we still have the expected number of items
    expect(items.size).to eq(4)
  end

  it 'validates that the CSS selector works as expected', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    doc = Nokogiri::HTML(File.read(html_file))
    matching_posts = doc.css('.main-content .post:not(.advertisement)')
    expect(matching_posts.size).to eq(4)
    matching_titles = matching_posts.filter_map { |post| post.at('h2')&.text }
    expect(matching_titles).to include('Breaking News: ACME Corp\'s Technology Breakthrough',
                                       'ACME Corp\'s Environmental Research Update',
                                       'ACME Corp\'s Economic Analysis Report',
                                       'ACME Corp\'s Developer Health and Wellness Tips')
    expect(matching_titles).not_to include('Sponsored Content: Buy ACME Corp\'s Product')
  end

  it 'parses ISO 8601 datetime format correctly from time elements', :aggregate_failures do
    items_with_time = items.select(&:pubDate)
    expect(items_with_time.size).to eq(4)
    expect(items_with_time).to all(have_attributes(pubDate: be_a(Time).and(have_attributes(year: 2024))))
  end

  it 'validates that attribute extraction works for datetime', :aggregate_failures do
    items = feed.items

    # All items should have published dates extracted from time[datetime] attributes
    items.each do |item|
      expect(item.pubDate).to be_a(Time)
      expect(item.pubDate.year).to eq(2024)
    end
  end

  it 'ensures performance optimization by using specific selectors', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    doc = Nokogiri::HTML(File.read(html_file))
    all_posts = doc.css('.post')
    optimized_posts = doc.css('.main-content .post:not(.advertisement)')
    expect(all_posts.size).to eq(7)
    expect(optimized_posts.size).to eq(4)
    expect(optimized_posts.size).to be < all_posts.size
  end
end
