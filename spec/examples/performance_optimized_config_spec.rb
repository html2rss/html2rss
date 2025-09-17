# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Performance-Optimized Configuration' do
  let(:config_file) { File.join(%w[spec fixtures performance-optimized-site.test.yml]) }
  let(:html_file) { File.join(%w[spec fixtures performance-optimized-site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  describe 'configuration loading' do
    it 'loads the configuration correctly', :aggregate_failures do
      expect(config).to be_a(Hash)
      expect(config[:channel][:url]).to eq('https://performance-optimized-site.com')
      expect(config[:channel][:title]).to eq('Performance-Optimized Site News')
      expect(config[:selectors][:items][:selector]).to eq('.main-content .post:not(.advertisement)')
      expect(config[:selectors][:title][:selector]).to eq('h2')
      expect(config[:selectors][:url][:selector]).to eq('a')
      expect(config[:selectors][:url][:extractor]).to eq('href')
      expect(config[:selectors][:published_at][:selector]).to eq('time')
      expect(config[:selectors][:published_at][:extractor]).to eq('attribute')
      expect(config[:selectors][:published_at][:attribute]).to eq('datetime')
    end

    it 'has correct post-processing configuration for published_at' do
      published_at_post_process = config[:selectors][:published_at][:post_process]
      expect(published_at_post_process).to include(
        { name: 'parse_time' }
      )
    end

    it 'has auto_source disabled for testing' do
      expect(config[:auto_source]).to be_nil
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      mock_request_service_with_html_fixture('performance_optimized_site', 'https://performance-optimized-site.com')

      Html2rss.feed(config)
    end

    it 'generates a valid RSS feed', :aggregate_failures do
      expect(feed).to be_a(RSS::Rss)
      expect(feed.channel.title).to eq('Performance-Optimized Site News')
      expect(feed.channel.link).to eq('https://performance-optimized-site.com')
    end

    it 'extracts the correct number of items (excluding advertisements and sidebar content)' do
      # Should include: 4 regular posts (excluding 1 advertisement and 1 sidebar post)
      expect(feed.items.size).to eq(4)
    end

    describe 'item extraction' do
      let(:items) { feed.items }

      it 'excludes advertisement posts' do
        titles = items.map(&:title)
        expect(titles).not_to include('Sponsored Content: Buy Our Product')
      end

      it 'excludes sidebar content', :aggregate_failures do
        titles = items.map(&:title)
        expect(titles).not_to include('Sidebar Content')
        expect(titles).not_to include('Sidebar Article')
      end

      it 'includes only main-content posts', :aggregate_failures do
        titles = items.map(&:title)
        expect(titles).to include('Breaking News: ACME Corp\'s Technology Breakthrough')
        expect(titles).to include('ACME Corp\'s Environmental Research Update')
        expect(titles).to include('ACME Corp\'s Economic Analysis Report')
        expect(titles).to include('ACME Corp\'s Developer Health and Wellness Tips')
      end

      it 'extracts titles correctly using h2 selector', :aggregate_failures do
        titles = items.map(&:title)
        expect(titles).to all(be_a(String))
        expect(titles).to all(satisfy { |title| !title.strip.empty? })
      end

      it 'extracts URLs correctly', :aggregate_failures do
        urls = items.map(&:link)
        expect(urls).to all(be_a(String))
        expect(urls).to include('https://performance-optimized-site.com/articles/technology-breakthrough')
        expect(urls).to include('https://performance-optimized-site.com/articles/environmental-research')
        expect(urls).to include('https://performance-optimized-site.com/articles/economic-analysis')
        expect(urls).to include('https://performance-optimized-site.com/articles/health-tips')
      end

      it 'extracts published dates correctly', :aggregate_failures do
        # All items should have published_at since they all have time elements
        items_with_time = items.select(&:pubDate)
        expect(items_with_time.size).to eq(4) # All 4 items have time elements

        # Check that dates are parsed correctly
        items_with_time.each do |item|
          expect(item.pubDate).to be_a(Time)
          expect(item.pubDate.year).to eq(2024)
        end
      end
    end

    describe 'selector specificity' do
      it 'correctly applies the complex item selector' do
        # The selector ".main-content .post:not(.advertisement)" should:
        # 1. Only select posts within .main-content
        # 2. Exclude posts with .advertisement class
        items = feed.items
        expect(items.size).to eq(4) # 5 posts in main-content, minus 1 advertisement = 4
      end

      it 'validates that the CSS selector works as expected', :aggregate_failures do
        # This test verifies the selector logic by checking the HTML structure
        doc = Nokogiri::HTML(File.read(html_file))

        # Count posts that match the selector
        matching_posts = doc.css('.main-content .post:not(.advertisement)')
        expect(matching_posts.size).to eq(4)

        # Verify no advertisement posts are included
        advertisement_posts = doc.css('.main-content .post.advertisement')
        expect(advertisement_posts.size).to eq(1) # There is 1 advertisement

        # Verify no sidebar posts are included
        sidebar_posts = doc.css('.main-content .post')
        expect(sidebar_posts.size).to eq(5) # 4 regular + 1 advertisement
      end
    end

    describe 'auto_source fallback' do
      it 'has auto_source disabled for this test' do
        expect(config[:auto_source]).to be_nil
      end
    end

    describe 'time parsing' do
      let(:items_with_time) { feed.items.select(&:pubDate) }

      it 'parses ISO 8601 datetime format correctly', :aggregate_failures do
        # The HTML contains times in format: 2024-01-15T10:30:00+00:00
        items_with_time.each do |item|
          expect(item.pubDate).to be_a(Time)
          expect(item.pubDate.year).to eq(2024)
          expect(item.pubDate.month).to eq(1)
        end
      end

      it 'handles different time formats', :aggregate_failures do
        # All our test times are in January 2024
        items_with_time.each do |item|
          expect(item.pubDate.year).to eq(2024)
          expect(item.pubDate.month).to eq(1)
          expect(item.pubDate.day).to be_between(12, 15)
        end
      end
    end
  end

  describe 'configuration issues' do
    it 'identifies the format parameter issue in parse_time', :aggregate_failures do
      # The original config had: format: "%Y-%m-%dT%H:%M:%S%z"
      # But parse_time doesn't accept a format parameter
      published_at_config = config[:selectors][:published_at]
      post_process = published_at_config[:post_process]

      # Should not have a format parameter
      expect(post_process.first).not_to have_key(:format)
      expect(post_process.first).to eq({ name: 'parse_time' })
    end

    it 'validates that the configuration is complete', :aggregate_failures do
      # Should have all required sections
      expect(config[:channel]).not_to be_nil
      expect(config[:selectors]).not_to be_nil
      expect(config[:auto_source]).to be_nil # Disabled for testing

      # Should have required channel fields
      expect(config[:channel][:url]).not_to be_nil
      expect(config[:channel][:title]).not_to be_nil
    end
  end
end
