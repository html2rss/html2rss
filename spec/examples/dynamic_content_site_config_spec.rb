# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dynamic Content Site Configuration' do
  let(:config_file) { File.join(%w[spec fixtures dynamic-content-site.test.yml]) }
  let(:html_file) { File.join(%w[spec fixtures dynamic-content-site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  describe 'configuration loading' do
    it 'loads the configuration correctly', :aggregate_failures do
      expect(config).to be_a(Hash)
      expect(config[:strategy]).to eq('browserless')
      expect(config[:channel][:url]).to eq('https://spa-example.com/news')
      expect(config[:channel][:title]).to eq('Dynamic Content Site News')
      expect(config[:channel][:time_zone]).to eq('America/New_York')
      expect(config[:selectors][:items][:selector]).to eq('.article-card')
      expect(config[:selectors][:title][:selector]).to eq('h2')
      expect(config[:selectors][:url][:selector]).to eq('a')
      expect(config[:selectors][:url][:extractor]).to eq('href')
      expect(config[:selectors][:description][:selector]).to eq('.excerpt')
      expect(config[:selectors][:published_at][:selector]).to eq('.timestamp')
    end

    it 'has correct post-processing configuration for description' do
      description_post_process = config[:selectors][:description][:post_process]
      expect(description_post_process).to include(
        { name: 'sanitize_html' }
      )
    end

    it 'has correct post-processing configuration for published_at' do
      published_at_post_process = config[:selectors][:published_at][:post_process]
      expect(published_at_post_process).to include(
        { name: 'parse_time' }
      )
    end

    it 'has browserless strategy configured' do
      expect(config[:strategy]).to eq('browserless')
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      mock_request_service_with_html_fixture('dynamic_content_site', 'https://spa-example.com/news')

      Html2rss.feed(config)
    end

    it 'generates a valid RSS feed', :aggregate_failures do
      expect(feed).to be_a(RSS::Rss)
      expect(feed.channel.title).to eq('Dynamic Content Site News')
      expect(feed.channel.link).to eq('https://spa-example.com/news')
    end

    it 'extracts the correct number of items' do
      expect(feed.items.size).to eq(6)
    end

    describe 'item extraction' do
      let(:items) { feed.items }

      it 'extracts titles correctly using h2 selector', :aggregate_failures do
        titles = items.map(&:title)
        expect(titles).to all(be_a(String))
        expect(titles).to include('ACME Corp\'s Revolutionary AI Breakthrough Changes Everything')
        expect(titles).to include('ACME Corp\'s Green Coding Summit Reaches Historic Agreement')
        expect(titles).to include('ACME Corp\'s Space Exploration Mission Discovers New Planet')
        expect(titles).to include('ACME Corp\'s Medical Breakthrough Offers Hope for Bug Patients')
        expect(titles).to include('ACME Corp\'s Renewable Energy Reaches New Milestone')
        expect(titles).to include('ACME Corp\'s Cybersecurity Threats Reach All-Time High')
      end

      it 'extracts URLs correctly using href extractor', :aggregate_failures do
        urls = items.map(&:link)
        expect(urls).to all(be_a(String))
        expect(urls).to include('https://spa-example.com/articles/ai-breakthrough-2024')
        expect(urls).to include('https://spa-example.com/articles/climate-summit-2024')
        expect(urls).to include('https://spa-example.com/articles/space-mission-discovery')
        expect(urls).to include('https://spa-example.com/articles/cancer-treatment-breakthrough')
        expect(urls).to include('https://spa-example.com/articles/renewable-energy-milestone')
        expect(urls).to include('https://spa-example.com/articles/cybersecurity-threats-2024')
      end

      it 'extracts descriptions correctly', :aggregate_failures do
        descriptions = items.map(&:description)
        expect(descriptions).to all(be_a(String))
        expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })

        # Check that descriptions contain expected content
        expect(descriptions).to include(match(/artificial intelligence system/i))
        expect(descriptions).to include(match(/green coding practices/i))
        expect(descriptions).to include(match(/potentially habitable planet/i))
        expect(descriptions).to include(match(/debugging treatment/i))
        expect(descriptions).to include(match(/renewable energy sources/i))
        expect(descriptions).to include(match(/cyber threats/i))
      end

      it 'extracts published dates correctly', :aggregate_failures do
        items_with_time = items.select(&:pubDate)
        expect(items_with_time.size).to eq(6) # All 6 items have timestamps

        # Check that dates are parsed correctly
        items_with_time.each do |item|
          expect(item.pubDate).to be_a(Time)
          expect(item.pubDate.year).to eq(2024)
          expect(item.pubDate.month).to eq(1) # All dates are in January
        end
      end
    end

    describe 'browserless strategy handling' do
      it 'configures browserless strategy for JavaScript-heavy content' do
        expect(config[:strategy]).to eq('browserless')
      end

      it 'handles dynamic content loading', :aggregate_failures do
        # The HTML fixture simulates dynamic content loading
        # In a real scenario, browserless would handle the JavaScript execution
        items = feed.items
        expect(items.size).to eq(6)

        # All items should be properly extracted despite being in a "dynamic" environment
        items.each do |item|
          expect(item.title).not_to be_nil
          expect(item.link).not_to be_nil
          expect(item.description).not_to be_nil
          expect(item.pubDate).not_to be_nil
        end
      end
    end

    describe 'time zone handling' do
      it 'respects the configured time zone' do
        expect(config[:channel][:time_zone]).to eq('America/New_York')
      end

      it 'parses timestamps in the correct format', :aggregate_failures do
        items_with_time = feed.items.select(&:pubDate)

        # All timestamps should be parsed correctly
        items_with_time.each do |item|
          expect(item.pubDate).to be_a(Time)
          expect(item.pubDate.year).to eq(2024)
        end
      end
    end

    describe 'URL extraction with href extractor' do
      let(:items) { feed.items }

      it 'uses href extractor for URL extraction', :aggregate_failures do
        url_config = config[:selectors][:url]
        expect(url_config[:extractor]).to eq('href')
        expect(url_config[:selector]).to eq('a')
      end

      it 'extracts URLs as absolute URLs' do
        urls = items.map(&:link)

        # All URLs should be absolute URLs (href extractor converts relative to absolute)
        expect(urls).to all(start_with('https://spa-example.com/articles/'))
      end

      it 'extracts different article URLs' do
        urls = items.map(&:link)
        expect(urls.uniq.size).to eq(6) # All URLs should be unique
      end
    end

    describe 'HTML sanitization' do
      let(:items) { feed.items }

      it 'applies HTML sanitization to descriptions' do
        description_config = config[:selectors][:description]
        post_process = description_config[:post_process]
        expect(post_process).to include({ name: 'sanitize_html' })
      end

      it 'sanitizes HTML content in descriptions', :aggregate_failures do
        descriptions = items.map(&:description)

        # Descriptions should be clean text without HTML tags
        descriptions.each do |desc|
          expect(desc).not_to match(/<[^>]+>/) # Should not contain HTML tags
          expect(desc).to be_a(String)
          expect(desc.strip).not_to be_empty
        end
      end
    end

    describe 'configuration issues' do
      it 'identifies the parse_time format parameter issue', :aggregate_failures do
        # The original config had: format: "%B %d, %Y at %I:%M %p"
        # But parse_time doesn't accept a format parameter
        published_at_config = config[:selectors][:published_at]
        post_process = published_at_config[:post_process]

        # Should not have a format parameter
        expect(post_process.first).not_to have_key(:format)
        expect(post_process.first).to eq({ name: 'parse_time' })
      end

      it 'validates that the configuration is complete', :aggregate_failures do
        # Should have all required sections
        expect(config[:strategy]).not_to be_nil
        expect(config[:channel]).not_to be_nil
        expect(config[:selectors]).not_to be_nil

        # Should have required channel fields
        expect(config[:channel][:url]).not_to be_nil
        expect(config[:channel][:title]).not_to be_nil
        expect(config[:channel][:time_zone]).not_to be_nil

        # Should have dynamic content selectors
        expect(config[:selectors][:url]).not_to be_nil
        expect(config[:selectors][:url][:extractor]).to eq('href')
        expect(config[:selectors][:published_at]).not_to be_nil
        expect(config[:selectors][:published_at][:post_process]).not_to be_nil
      end

      it 'validates browserless strategy configuration', :aggregate_failures do
        expect(config[:strategy]).to eq('browserless')
        expect(config[:strategy]).not_to be_nil
      end

      it 'validates time parsing configuration', :aggregate_failures do
        published_at_config = config[:selectors][:published_at]
        expect(published_at_config[:selector]).to eq('.timestamp')
        expect(published_at_config[:post_process]).to include({ name: 'parse_time' })
      end
    end
  end
end
