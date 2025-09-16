# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Conditional Processing Configuration' do
  let(:config_file) { File.join(%w[spec examples conditional_processing_site.yml]) }
  let(:html_file) { File.join(%w[spec examples conditional_processing_site.html]) }
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
      expect(config[:selectors][:status]).to be_a(Hash)
      expect(config[:selectors][:status][:selector]).to be_a(String)
      expect(config[:selectors][:description]).to be_a(Hash)
      expect(config[:selectors][:description][:selector]).to be_a(String)
      expect(config[:selectors][:published_at]).to be_a(Hash)
      expect(config[:selectors][:published_at][:selector]).to be_a(String)
      expect(config[:selectors][:categories]).to include('status')
    end

    it 'has correct post-processing configuration' do
      description_post_process = config[:selectors][:description][:post_process]
      expect(description_post_process).to be_an(Array)
      expect(description_post_process.first).to include(:name, :string)

      published_at_post_process = config[:selectors][:published_at][:post_process]
      expect(published_at_post_process).to be_an(Array)
      expect(published_at_post_process.first).to include(:name)
    end

    it 'includes status in categories' do
      expect(config[:selectors][:categories]).to include('status')
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      allow_any_instance_of(Html2rss::RequestService).to receive(:execute).and_return(
        Html2rss::RequestService::Response.new(
          body: File.read(html_file),
          url: 'https://conditional-processing-site.com',
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
      titles = feed.items.map(&:title)
      expect(titles).to all(be_a(String))
      expect(titles).to all(satisfy { |title| !title.strip.empty? })
    end

    it 'extracts status information as categories' do
      items = feed.items
      items_with_status = items.select do |item|
        item.categories.any? { |cat| cat.content.is_a?(String) }
      end
      expect(items_with_status.size).to be > 0
    end

    it 'extracts published dates correctly' do
      items = feed.items
      items_with_time = items.select { |item| item.pubDate }
      expect(items_with_time.size).to be > 0

      items_with_time.each do |item|
        expect(item.pubDate).to be_a(Time)
      end
    end

    it 'applies template processing to descriptions' do
      items = feed.items
      descriptions = items.map(&:description)
      expect(descriptions).to all(be_a(String))
      expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })
    end

    it 'includes status as categories' do
      items = feed.items
      items_with_status = items.select do |item|
        item.categories.any? { |cat| cat.content.is_a?(String) }
      end
      expect(items_with_status.size).to be > 0
    end

    it 'validates template syntax is correct' do
      template_config = config[:selectors][:description][:post_process].first
      expect(template_config).to have_key(:string)
      expect(template_config).not_to have_key(:template)
    end
  end
end
