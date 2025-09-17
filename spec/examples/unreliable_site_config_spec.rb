# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Unreliable Site Configuration' do
  let(:config_file) { File.join(%w[spec fixtures unreliable-site.test.yml]) }
  let(:html_file) { File.join(%w[spec fixtures unreliable-site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  describe 'configuration loading' do
    it 'loads the configuration correctly', :aggregate_failures do
      expect(config).to be_a(Hash)
      expect(config[:channel][:url]).to eq('https://unreliable-site.com')
      expect(config[:channel][:ttl]).to eq(60)
      expect(config[:selectors][:items][:selector]).to eq('.post, .article')
      expect(config[:selectors][:title][:selector]).to eq('h1, h2, .title')
      expect(config[:selectors][:description][:selector]).to eq('.content, .excerpt, p')
      expect(config[:selectors][:url][:selector]).to eq('a')
      expect(config[:selectors][:url][:extractor]).to eq('href')
    end

    it 'has correct post-processing configuration', :aggregate_failures do
      description_post_process = config[:selectors][:description][:post_process]
      expect(description_post_process).to include(
        { name: 'sanitize_html' },
        { name: 'substring', start: 0, end: 499 }
      )

      url_post_process = config[:selectors][:url][:post_process]
      expect(url_post_process).to include(
        { name: 'parse_uri' }
      )
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      mock_request_service_with_html_fixture('unreliable_site', 'https://unreliable-site.com')

      Html2rss.feed(config)
    end

    it 'generates a valid RSS feed', :aggregate_failures do
      expect(feed).to be_a(RSS::Rss)
      expect(feed.channel.title).to eq('ACME Unreliable Site - News and Articles')
      expect(feed.channel.link).to eq('https://unreliable-site.com')
      expect(feed.channel.ttl).to eq(60)
    end

    it 'extracts the correct number of items' do
      expect(feed.items.size).to eq(5)
    end

    describe 'item extraction' do
      let(:items) { feed.items }

      it 'extracts titles correctly using fallback selectors', :aggregate_failures do
        titles = items.map(&:title)
        expect(titles).to include('Breaking News: ACME Corp\'s Technology Advances')
        expect(titles).to include('ACME Corp Science Discovery: New Findings')
        expect(titles).to include('ACME Corp Environmental Impact Report')
        expect(titles).to include('ACME Corp Economic Analysis: Market Trends')
        expect(titles).to include('ACME Corp Developer Health and Wellness Update')
      end

      it 'extracts URLs correctly with parse_uri post-processing', :aggregate_failures do
        urls = items.map(&:link)
        expect(urls).to all(be_a(String))
        expect(urls).to all(include('/articles/'))
        expect(urls).to include('https://unreliable-site.com/articles/breaking-news-technology-advances')
        expect(urls).to include('https://unreliable-site.com/articles/science-discovery-new-findings')
        expect(urls).to include('https://unreliable-site.com/articles/environmental-impact-report')
        expect(urls).to include('https://unreliable-site.com/articles/economic-analysis-market-trends')
        expect(urls).to include('https://unreliable-site.com/articles/health-wellness-update')
      end

      it 'extracts descriptions with proper post-processing', :aggregate_failures do
        descriptions = items.map(&:description)

        # All descriptions should be strings
        expect(descriptions).to all(be_a(String))

        # Descriptions should be sanitized (no script tags, etc.)
        descriptions.each do |desc|
          expect(desc).not_to include('<script')
          expect(desc).not_to include('javascript:')

          # Descriptions should be truncated to 500 characters
          expect(desc.length).to be <= 500
        end

        # Check that we have meaningful content
        expect(descriptions).to all(satisfy { |desc| desc.length > 10 })
      end

      it 'handles multiple selector fallbacks for items' do
        # Verify that both .post and .article selectors are working
        # by checking that we get items from both types
        expect(items.size).to eq(5) # 3 .post + 2 .article = 5 total
      end

      it 'handles multiple selector fallbacks for titles', :aggregate_failures do
        # Verify that h1, h2, and .title selectors all work
        titles = items.map(&:title)

        # Should have titles from h1, h2, and .title elements
        expect(titles).to include('ACME Corp Science Discovery: New Findings') # h1
        expect(titles).to include('Breaking News: ACME Corp\'s Technology Advances') # h2
        expect(titles).to include('ACME Corp Environmental Impact Report') # .title
      end

      it 'handles multiple selector fallbacks for descriptions', :aggregate_failures do
        # Verify that .content, .excerpt, and p selectors all work
        descriptions = items.map(&:description)

        # All descriptions should have content
        expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })

        # Should have descriptions from different selector types
        # (This is harder to test specifically without knowing the exact order,
        # but we can verify that descriptions are being extracted)
        expect(descriptions.size).to eq(5)
      end
    end

    describe 'post-processing validation' do
      let(:first_item) { feed.items.first }

      it 'applies sanitize_html post-processing', :aggregate_failures do
        # The description should be sanitized HTML
        expect(first_item.description).to be_a(String)
        # Should not contain potentially dangerous HTML
        expect(first_item.description).not_to match(/<script|javascript:|on\w+=/i)
      end

      it 'applies substring post-processing with correct length limit' do
        # Description should be truncated to 500 characters
        expect(first_item.description.length).to be <= 500
      end

      it 'applies parse_uri post-processing to URLs', :aggregate_failures do
        # URL should be accessible via the link property
        expect(first_item.link).to be_a(String)
        expect(first_item.link).to include('/articles/')
      end
    end

    describe 'TTL configuration' do
      it 'sets the correct TTL value' do
        expect(feed.channel.ttl).to eq(60)
      end
    end
  end
end
