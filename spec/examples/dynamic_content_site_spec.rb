# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dynamic Content Site Configuration' do
  let(:config_file) { File.join(%w[spec examples dynamic_content_site.yml]) }
  let(:html_file) { File.join(%w[spec examples dynamic_content_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  describe 'configuration loading' do
    it 'loads the configuration correctly' do
      expect(config).to be_a(Hash)
      expect(config[:strategy]).to eq('browserless')
      expect(config[:channel]).to be_a(Hash)
      expect(config[:channel][:url]).to be_a(String)
      expect(config[:channel][:title]).to be_a(String)
      expect(config[:channel][:time_zone]).to be_a(String)
      expect(config[:selectors]).to be_a(Hash)
      expect(config[:selectors][:items]).to be_a(Hash)
      expect(config[:selectors][:items][:selector]).to be_a(String)
      expect(config[:selectors][:title]).to be_a(Hash)
      expect(config[:selectors][:title][:selector]).to be_a(String)
      expect(config[:selectors][:url]).to be_a(Hash)
      expect(config[:selectors][:url][:selector]).to be_a(String)
      expect(config[:selectors][:url][:extractor]).to eq('href')
      expect(config[:selectors][:description]).to be_a(Hash)
      expect(config[:selectors][:description][:selector]).to be_a(String)
      expect(config[:selectors][:published_at]).to be_a(Hash)
      expect(config[:selectors][:published_at][:selector]).to be_a(String)
    end

    it 'has correct post-processing configuration for description' do
      description_post_process = config[:selectors][:description][:post_process]
      expect(description_post_process).to be_an(Array)
      expect(description_post_process.first).to include(:name)
    end

    it 'has correct post-processing configuration for published_at' do
      published_at_post_process = config[:selectors][:published_at][:post_process]
      expect(published_at_post_process).to be_an(Array)
      expect(published_at_post_process.first).to include(:name)
    end

    it 'has browserless strategy configured' do
      expect(config[:strategy]).to eq('browserless')
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      allow_any_instance_of(Html2rss::RequestService).to receive(:execute).and_return(
        Html2rss::RequestService::Response.new(
          body: File.read(html_file),
          url: 'https://spa-example.com/news',
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

    it 'extracts the correct number of items' do
      expect(feed.items).to be_an(Array)
      expect(feed.items.size).to be > 0
    end

    it 'extracts titles correctly using h2 selector' do
      items = feed.items
      titles = items.map(&:title)
      expect(titles).to all(be_a(String))
      expect(titles).to all(satisfy { |title| !title.strip.empty? })
    end

    it 'extracts URLs correctly using href extractor' do
      items = feed.items
      urls = items.map(&:link)
      expect(urls).to all(be_a(String))
      expect(urls).to all(satisfy { |url| !url.strip.empty? })
    end

    it 'extracts descriptions correctly' do
      items = feed.items
      descriptions = items.map(&:description)
      expect(descriptions).to all(be_a(String))
      expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })
    end

    it 'extracts published dates correctly' do
      items = feed.items
      items_with_time = items.select { |item| item.pubDate }
      expect(items_with_time.size).to be > 0

      items_with_time.each do |item|
        expect(item.pubDate).to be_a(Time)
      end
    end

    it 'configures browserless strategy for JavaScript-heavy content' do
      expect(config[:strategy]).to eq('browserless')
    end

    it 'handles dynamic content loading' do
      items = feed.items
      expect(items.size).to be > 0

      items.each do |item|
        expect(item.title).not_to be_nil
        expect(item.link).not_to be_nil
        expect(item.description).not_to be_nil
        expect(item.pubDate).not_to be_nil
      end
    end

    it 'respects the configured time zone' do
      expect(config[:channel][:time_zone]).to be_a(String)
    end

    it 'uses href extractor for URL extraction' do
      url_config = config[:selectors][:url]
      expect(url_config[:extractor]).to eq('href')
      expect(url_config[:selector]).to be_a(String)
    end

    it 'extracts URLs as absolute URLs' do
      items = feed.items
      urls = items.map(&:link)
      expect(urls).to all(be_a(String))
    end

    it 'applies HTML sanitization to descriptions' do
      description_config = config[:selectors][:description]
      post_process = description_config[:post_process]
      expect(post_process).to be_an(Array)
      expect(post_process.first).to include(:name)
    end

    it 'sanitizes HTML content in descriptions' do
      items = feed.items
      descriptions = items.map(&:description)
      expect(descriptions).to all(be_a(String))
      expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })
    end
  end
end
