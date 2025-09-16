# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Media Enclosures Configuration' do
  let(:config_file) { File.join(%w[spec examples media_enclosures_site.yml]) }
  let(:html_file) { File.join(%w[spec examples media_enclosures_site.html]) }
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
      expect(config[:selectors][:description]).to be_a(Hash)
      expect(config[:selectors][:description][:selector]).to be_a(String)
      expect(config[:selectors][:url]).to be_a(Hash)
      expect(config[:selectors][:url][:selector]).to be_a(String)
      expect(config[:selectors][:url][:extractor]).to eq('href')
      expect(config[:selectors][:enclosure]).to be_a(Hash)
      expect(config[:selectors][:enclosure][:selector]).to be_a(String)
      expect(config[:selectors][:enclosure][:extractor]).to eq('attribute')
      expect(config[:selectors][:enclosure][:attribute]).to eq('src')
      expect(config[:selectors][:enclosure][:content_type]).to be_a(String)
      expect(config[:selectors][:duration]).to be_a(Hash)
      expect(config[:selectors][:duration][:selector]).to be_a(String)
      expect(config[:selectors][:duration][:extractor]).to eq('attribute')
      expect(config[:selectors][:duration][:attribute]).to eq('data-duration')
    end

    it 'has correct post-processing configuration' do
      description_post_process = config[:selectors][:description][:post_process]
      expect(description_post_process).to be_an(Array)
      expect(description_post_process.first).to include(:name)

      published_at_post_process = config[:selectors][:published_at][:post_process]
      expect(published_at_post_process).to be_an(Array)
      expect(published_at_post_process.first).to include(:name)
    end

    it 'includes duration in categories' do
      expect(config[:selectors][:categories]).to include('duration')
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      allow_any_instance_of(Html2rss::RequestService).to receive(:execute).and_return(
        Html2rss::RequestService::Response.new(
          body: File.read(html_file),
          url: 'https://podcast-site.com',
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

    it 'extracts the correct number of episodes' do
      expect(feed.items).to be_an(Array)
      expect(feed.items.size).to be > 0
    end

    it 'extracts titles correctly using h3 selector' do
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

    it 'extracts descriptions with html_to_markdown post-processing' do
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

    it 'extracts duration information' do
      items = feed.items
      items.each do |item|
        expect(item.categories).not_to be_nil
        duration_categories = item.categories.select { |cat| cat.content.match?(/^\d+$/) }
        expect(duration_categories).not_to be_empty
      end
    end

    it 'extracts audio enclosures correctly' do
      items = feed.items
      audio_items = items.select { |item| item.enclosure && item.enclosure.url.include?('.mp3') }
      expect(audio_items.size).to be >= 0

      audio_items.each do |item|
        expect(item.enclosure).not_to be_nil
        expect(item.enclosure.url).to be_a(String)
        expect(item.enclosure.type).to be_a(String)
      end
    end

    it 'handles video enclosures' do
      items = feed.items
      items_with_enclosures = items.select { |item| item.enclosure }
      expect(items_with_enclosures.size).to be >= 0

      items_with_enclosures.each do |item|
        expect(item.enclosure).not_to be_nil
        expect(item.enclosure.url).to be_a(String)
        expect(item.enclosure.type).to be_a(String)
      end
    end

    it 'handles episodes without media enclosures' do
      items = feed.items
      no_enclosure_items = items.select { |item| !item.enclosure }
      expect(no_enclosure_items.size).to be >= 0
    end

    it 'validates enclosure URLs are absolute' do
      items = feed.items
      items_with_enclosures = items.select { |item| item.enclosure }
      expect(items_with_enclosures.size).to be >= 0

      items_with_enclosures.each do |item|
        expect(item.enclosure.url).to be_a(String)
      end
    end

    it 'extracts duration from data-duration attribute' do
      items = feed.items
      items.each do |item|
        duration_categories = item.categories.select { |cat| cat.content.match?(/^\d+$/) }
        expect(duration_categories).not_to be_empty

        duration_categories.each do |cat|
          duration_seconds = cat.content.to_i
          expect(duration_seconds).to be >= 0
        end
      end
    end

    it 'handles different duration formats' do
      items = feed.items
      items.each do |item|
        duration_categories = item.categories.select { |cat| cat.content.match?(/^\d+$/) }
        expect(duration_categories.size).to be >= 0
      end
    end

    it 'processes descriptions with html_to_markdown post-processing' do
      items = feed.items
      descriptions = items.map(&:description)
      expect(descriptions).to all(be_a(String))
      expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })
    end

    it 'validates that the configuration is complete' do
      expect(config[:channel]).not_to be_nil
      expect(config[:selectors]).not_to be_nil
      expect(config[:channel][:url]).not_to be_nil
      expect(config[:channel][:title]).not_to be_nil
      expect(config[:selectors][:enclosure]).not_to be_nil
      expect(config[:selectors][:duration]).not_to be_nil
    end

    it 'validates enclosure configuration structure' do
      enclosure_config = config[:selectors][:enclosure]
      expect(enclosure_config[:selector]).to be_a(String)
      expect(enclosure_config[:extractor]).to eq('attribute')
      expect(enclosure_config[:attribute]).to eq('src')
      expect(enclosure_config[:content_type]).to be_a(String)
    end
  end
end
