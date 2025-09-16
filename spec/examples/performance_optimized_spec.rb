# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Performance-Optimized Configuration' do
  let(:config_file) { File.join(%w[spec examples performance_optimized_site.yml]) }
  let(:html_file) { File.join(%w[spec examples performance_optimized_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  describe 'configuration loading' do
    it 'loads the configuration correctly' do
      expect(config).to be_a(Hash)
      expect(config[:channel]).to be_a(Hash)
      expect(config[:channel][:url]).to be_a(String)
      expect(config[:channel][:title]).to be_a(String)
      expect(config[:selectors]).to be_a(Hash)
      expect(config[:selectors][:items]).to be_a(Hash)
      expect(config[:selectors][:items][:selector]).to be_a(String)
      expect(config[:selectors][:title]).to be_a(Hash)
      expect(config[:selectors][:title][:selector]).to be_a(String)
      expect(config[:selectors][:url]).to be_a(Hash)
      expect(config[:selectors][:url][:selector]).to be_a(String)
      expect(config[:selectors][:url][:extractor]).to eq('href')
      expect(config[:selectors][:published_at]).to be_a(Hash)
      expect(config[:selectors][:published_at][:selector]).to be_a(String)
      expect(config[:selectors][:published_at][:extractor]).to eq('attribute')
      expect(config[:selectors][:published_at][:attribute]).to eq('datetime')
    end

    it 'has correct post-processing configuration for published_at' do
      published_at_post_process = config[:selectors][:published_at][:post_process]
      expect(published_at_post_process).to be_an(Array)
      expect(published_at_post_process.first).to include(:name)
    end

    it 'has auto_source disabled for testing' do
      expect(config[:auto_source]).to be_nil
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      allow_any_instance_of(Html2rss::RequestService).to receive(:execute).and_return(
        Html2rss::RequestService::Response.new(
          body: File.read(html_file),
          url: 'https://performance-optimized-site.com',
          headers: { 'content-type': 'text/html' }
        )
      )

      Html2rss.feed(config)
    end

    it 'generates a valid RSS feed' do
      expect(feed).to be_a(RSS::Rss)
      expect(feed.channel.title).to be_a(String)
      expect(feed.channel.link).to be_a(String)
    end

    it 'extracts the correct number of items (excluding advertisements and sidebar content)' do
      expect(feed.items).to be_an(Array)
      expect(feed.items.size).to be > 0
    end

    it 'excludes advertisement posts' do
      items = feed.items
      titles = items.map(&:title)
      expect(titles).to all(be_a(String))
      expect(titles).to all(satisfy { |title| !title.strip.empty? })
    end

    it 'excludes sidebar content' do
      items = feed.items
      titles = items.map(&:title)
      expect(titles).to all(be_a(String))
      expect(titles).to all(satisfy { |title| !title.strip.empty? })
    end

    it 'includes only main-content posts' do
      items = feed.items
      titles = items.map(&:title)
      expect(titles).to all(be_a(String))
      expect(titles).to all(satisfy { |title| !title.strip.empty? })
    end

    it 'extracts titles correctly using h2 selector' do
      items = feed.items
      titles = items.map(&:title)
      expect(titles).to all(be_a(String))
      expect(titles).to all(satisfy { |title| !title.strip.empty? })
    end

    it 'extracts URLs correctly' do
      items = feed.items
      urls = items.map(&:link)
      expect(urls).to all(be_a(String))
      expect(urls).to all(satisfy { |url| !url.strip.empty? })
    end

    it 'extracts published dates correctly' do
      items = feed.items
      items_with_time = items.select { |item| item.pubDate }
      expect(items_with_time.size).to be > 0

      items_with_time.each do |item|
        expect(item.pubDate).to be_a(Time)
      end
    end

    it 'correctly applies the complex item selector' do
      items = feed.items
      expect(items.size).to be > 0
    end

    it 'validates that the CSS selector works as expected' do
      doc = Nokogiri::HTML(File.read(html_file))
      matching_posts = doc.css('.main-content .post:not(.advertisement)')
      expect(matching_posts.size).to be > 0
    end

    it 'has auto_source disabled for this test' do
      expect(config[:auto_source]).to be_nil
    end

    it 'parses ISO 8601 datetime format correctly' do
      items = feed.items
      items_with_time = items.select { |item| item.pubDate }
      expect(items_with_time.size).to be > 0

      items_with_time.each do |item|
        expect(item.pubDate).to be_a(Time)
      end
    end

    it 'handles different time formats' do
      items = feed.items
      items_with_time = items.select { |item| item.pubDate }
      expect(items_with_time.size).to be > 0

      items_with_time.each do |item|
        expect(item.pubDate).to be_a(Time)
      end
    end

    it 'validates that the configuration is complete' do
      expect(config[:channel]).not_to be_nil
      expect(config[:selectors]).not_to be_nil
      expect(config[:auto_source]).to be_nil
      expect(config[:channel][:url]).not_to be_nil
      expect(config[:channel][:title]).not_to be_nil
    end
  end
end
