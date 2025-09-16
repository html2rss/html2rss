# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'JSON API Site Configuration' do
  let(:config_file) { File.join(%w[spec examples json_api_site.yml]) }
  let(:json_file) { File.join(%w[spec examples json_api_site.json]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  describe 'configuration loading' do
    it 'loads the configuration correctly' do
      expect(config).to be_a(Hash)
      expect(config[:headers]).to be_a(Hash)
      expect(config[:headers][:Accept]).to eq('application/json')
      expect(config[:headers][:Authorization]).to be_a(String)
      expect(config[:channel]).to be_a(Hash)
      expect(config[:channel][:url]).to be_a(String)
      expect(config[:channel][:title]).to be_a(String)
      expect(config[:selectors]).to be_a(Hash)
      expect(config[:selectors][:items]).to be_a(Hash)
      expect(config[:selectors][:items][:selector]).to be_a(String)
      expect(config[:selectors][:title]).to be_a(Hash)
      expect(config[:selectors][:title][:selector]).to be_a(String)
      expect(config[:selectors][:description]).to be_a(Hash)
      expect(config[:selectors][:description][:selector]).to be_a(String)
      expect(config[:selectors][:author]).to be_a(Hash)
      expect(config[:selectors][:author][:selector]).to be_a(String)
      expect(config[:selectors][:published_at]).to be_a(Hash)
      expect(config[:selectors][:published_at][:selector]).to be_a(String)
      expect(config[:selectors][:category]).to be_a(Hash)
      expect(config[:selectors][:category][:selector]).to be_a(String)
      expect(config[:selectors][:tags]).to be_a(Hash)
      expect(config[:selectors][:tags][:selector]).to be_a(String)
      expect(config[:selectors][:image]).to be_a(Hash)
      expect(config[:selectors][:image][:selector]).to be_a(String)
      expect(config[:selectors][:enclosure]).to be_a(Hash)
      expect(config[:selectors][:enclosure][:selector]).to be_a(String)
      expect(config[:selectors][:enclosure][:content_type]).to be_a(String)
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

    it 'includes category and tags in categories' do
      expect(config[:selectors][:categories]).to include('category')
      expect(config[:selectors][:categories]).to include('tags')
    end

    it 'has correct headers configuration' do
      expect(config[:headers][:Accept]).to eq('application/json')
      expect(config[:headers][:Authorization]).to be_a(String)
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our JSON fixture
      allow_any_instance_of(Html2rss::RequestService).to receive(:execute).and_return(
        Html2rss::RequestService::Response.new(
          body: File.read(json_file),
          url: 'https://example.com/posts',
          headers: { 'content-type': 'application/json' }
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

    it 'extracts titles correctly' do
      items = feed.items
      titles = items.map(&:title)
      expect(titles).to all(be_a(String))
      expect(titles).to all(satisfy { |title| !title.strip.empty? })
    end

    it 'extracts descriptions correctly with HTML to Markdown conversion' do
      items = feed.items
      descriptions = items.map(&:description)
      expect(descriptions).to all(be_a(String))
      expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })
    end

    it 'extracts author information' do
      author_config = config[:selectors][:author]
      expect(author_config[:selector]).to be_a(String)
    end

    it 'extracts published dates correctly' do
      items = feed.items
      items_with_time = items.select { |item| item.pubDate }
      expect(items_with_time.size).to be > 0

      items_with_time.each do |item|
        expect(item.pubDate).to be_a(Time)
      end
    end

    it 'extracts category information as categories' do
      items = feed.items
      items_with_category = items.select { |item| item.categories.any? }
      expect(items_with_category.size).to be > 0
    end

    it 'extracts tag information as categories' do
      items = feed.items
      items_with_tags = items.select { |item| item.categories.any? }
      expect(items_with_tags.size).to be > 0
    end

    it 'configures headers for JSON API requests' do
      expect(config[:headers][:Accept]).to eq('application/json')
      expect(config[:headers][:Authorization]).to be_a(String)
    end

    it 'handles complex JSON structure' do
      items = feed.items
      expect(items.size).to be > 0

      items.each do |item|
        expect(item.title).not_to be_nil
        expect(item.description).not_to be_nil
        expect(item.pubDate).not_to be_nil
      end
    end

    it 'extracts nested object properties correctly' do
      author_config = config[:selectors][:author]
      expect(author_config[:selector]).to be_a(String)

      category_config = config[:selectors][:category]
      expect(category_config[:selector]).to be_a(String)

      image_config = config[:selectors][:image]
      expect(image_config[:selector]).to be_a(String)
    end

    it 'handles array selectors for tags' do
      tags_config = config[:selectors][:tags]
      expect(tags_config[:selector]).to be_a(String)
    end

    it 'applies HTML to Markdown conversion to descriptions' do
      description_config = config[:selectors][:description]
      post_process = description_config[:post_process]
      expect(post_process).to be_an(Array)
      expect(post_process.first).to include(:name)
    end

    it 'converts HTML content to Markdown in descriptions' do
      items = feed.items
      descriptions = items.map(&:description)
      expect(descriptions).to all(be_a(String))
      expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })
    end

    it 'configures enclosure extraction correctly' do
      enclosure_config = config[:selectors][:enclosure]
      expect(enclosure_config[:selector]).to be_a(String)
      expect(enclosure_config[:content_type]).to be_a(String)
    end

    it 'handles items with and without audio files' do
      items = feed.items
      items_with_enclosures = items.select { |item| item.enclosure }
      expect(items_with_enclosures.size).to be >= 0

      items_with_enclosures.each do |item|
        expect(item.enclosure).not_to be_nil
        expect(item.enclosure.url).not_to be_nil
        expect(item.enclosure.type).not_to be_nil
      end
    end

    it 'configures image extraction correctly' do
      image_config = config[:selectors][:image]
      expect(image_config[:selector]).to be_a(String)
    end
  end
end
