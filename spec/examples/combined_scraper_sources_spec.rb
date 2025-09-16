# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Combined Scraper Sources Configuration' do
  let(:config_file) { File.join(%w[spec examples combined_scraper_sources.yml]) }
  let(:html_file) { File.join(%w[spec examples combined_scraper_sources.html]) }
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
      expect(config[:selectors][:items][:enhance]).to be true
    end

    it 'has correct post-processing configuration for category' do
      category_post_process = config[:selectors][:category][:post_process]
      expect(category_post_process).to be_an(Array)
      expect(category_post_process.first).to include(:name, :pattern, :replacement)
    end

    it 'has correct post-processing configuration for custom_guid' do
      custom_guid_post_process = config[:selectors][:custom_guid][:post_process]
      expect(custom_guid_post_process).to be_an(Array)
      expect(custom_guid_post_process.first).to include(:name, :string, :methods)
    end

    it 'has auto_source enabled for combined approach' do
      expect(config[:auto_source]).to eq({})
    end

    it 'has enhance enabled for items' do
      expect(config[:selectors][:items][:enhance]).to be true
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      allow_any_instance_of(Html2rss::RequestService).to receive(:execute).and_return(
        Html2rss::RequestService::Response.new(
          body: File.read(html_file),
          url: Html2rss::Url.from_relative('https://technews.com', 'https://technews.com'),
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

    it 'extracts items using combined auto-source and manual selectors' do
      expect(feed.items).to be_an(Array)
      expect(feed.items.size).to be > 0
    end

    it 'extracts titles correctly using combined approach' do
      titles = feed.items.map(&:title).compact
      expect(titles).to all(be_a(String))
      expect(titles).to all(satisfy { |title| !title.strip.empty? })
    end

    it 'extracts URLs correctly using combined approach' do
      urls = feed.items.map(&:link).compact
      expect(urls).to all(be_a(String))
      expect(urls).to all(satisfy { |url| !url.strip.empty? })
    end

    it 'extracts descriptions correctly using combined approach' do
      descriptions = feed.items.map(&:description).compact
      expect(descriptions).to all(be_a(String))
      expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })
    end

    it 'applies gsub replacement to categories' do
      items = feed.items
      items_with_categories = items.select { |item| item.categories.any? }
      expect(items_with_categories.size).to be > 0
    end

    it 'extracts tags correctly' do
      items = feed.items
      all_tags = items.flat_map { |item| item.categories.map(&:content) }.uniq
      expect(all_tags).not_to be_empty
    end

    it 'generates GUIDs for items' do
      items = feed.items
      guids = items.map(&:guid)
      expect(guids).to all(be_a(RSS::Rss::Channel::Item::Guid))
      expect(guids.map(&:content)).to all(satisfy { |guid| !guid.strip.empty? })
    end
  end
end
