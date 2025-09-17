# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Unreliable Site Configuration' do
  let(:config_file) { File.join(%w[spec examples unreliable_site.yml]) }
  let(:html_file) { File.join(%w[spec examples unreliable_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  describe 'configuration loading' do
    it 'loads the configuration correctly', :aggregate_failures do
      expect(config).to be_a(Hash)
      expect(config[:channel]).to be_a(Hash)
      expect(config[:channel][:url]).to be_a(String)
      expect(config[:channel][:ttl]).to be_a(Integer)
      expect(config[:selectors]).to be_a(Hash)
      expect(config[:selectors][:items]).to be_a(Hash)
      expect(config[:selectors][:items][:selector]).to be_a(String)
      expect(config[:selectors][:title]).to be_a(Hash)
      expect(config[:selectors][:title][:selector]).to be_a(String)
      expect(config[:selectors][:description]).to be_a(Hash)
      expect(config[:selectors][:description][:selector]).to be_a(String)
      expect(config[:selectors][:url]).to be_a(Hash)
      expect(config[:selectors][:url][:selector]).to be_a(String)
      expect(config[:selectors][:url][:extractor]).to eq('href')
    end

    it 'has correct post-processing configuration', :aggregate_failures do
      description_post_process = config[:selectors][:description][:post_process]
      expect(description_post_process).to be_an(Array)
      expect(description_post_process.first).to include(:name)
      expect(description_post_process.last).to include(:name, :start, :end)

      url_post_process = config[:selectors][:url][:post_process]
      expect(url_post_process).to be_an(Array)
      expect(url_post_process.first).to include(:name)
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      mock_request_service_with_html_fixture('unreliable_site', 'https://example.com')

      Html2rss.feed(config)
    end

    it 'generates a valid RSS feed', :aggregate_failures do
      expect(feed).to be_a(RSS::Rss)
      expect(feed.channel.title).to be_a(String)
      expect(feed.channel.link).to be_a(String)
      expect(feed.channel.ttl).to be_a(Integer)
    end

    it 'extracts the correct number of items', :aggregate_failures do
      expect(feed.items).to be_an(Array)
      expect(feed.items.size).to be > 0
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
end
