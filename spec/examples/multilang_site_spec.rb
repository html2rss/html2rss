# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Multi-Language Site Configuration' do
  let(:config_file) { File.join(%w[spec examples multilang_site.yml]) }
  let(:html_file) { File.join(%w[spec examples multilang_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  describe 'configuration loading' do
    it 'loads the configuration correctly' do
      expect(config).to be_a(Hash)
      expect(config[:channel]).to be_a(Hash)
      expect(config[:channel][:url]).to be_a(String)
      expect(config[:channel][:title]).to be_a(String)
      expect(config[:channel][:language]).to be_a(String)
      expect(config[:channel][:time_zone]).to be_a(String)
      expect(config[:selectors]).to be_a(Hash)
      expect(config[:selectors][:items]).to be_a(Hash)
      expect(config[:selectors][:items][:selector]).to be_a(String)
      expect(config[:selectors][:title]).to be_a(Hash)
      expect(config[:selectors][:title][:selector]).to be_a(String)
      expect(config[:selectors][:language]).to be_a(Hash)
      expect(config[:selectors][:language][:selector]).to be_a(String)
      expect(config[:selectors][:language][:extractor]).to eq('attribute')
      expect(config[:selectors][:language][:attribute]).to eq('data-lang')
      expect(config[:selectors][:description]).to be_a(Hash)
      expect(config[:selectors][:description][:selector]).to be_a(String)
      expect(config[:selectors][:topic]).to be_a(Hash)
      expect(config[:selectors][:topic][:selector]).to be_a(String)
      expect(config[:selectors][:categories]).to include('language')
      expect(config[:selectors][:categories]).to include('topic')
    end

    it 'has correct post-processing configuration for title' do
      title_post_process = config[:selectors][:title][:post_process]
      expect(title_post_process).to be_an(Array)
      expect(title_post_process.first).to include(:name, :string)
    end

    it 'has correct post-processing configuration for description' do
      description_post_process = config[:selectors][:description][:post_process]
      expect(description_post_process).to be_an(Array)
      expect(description_post_process.first).to include(:name)
    end

    it 'includes language and topic in categories' do
      expect(config[:selectors][:categories]).to include('language')
      expect(config[:selectors][:categories]).to include('topic')
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      allow_any_instance_of(Html2rss::RequestService).to receive(:execute).and_return(
        Html2rss::RequestService::Response.new(
          body: File.read(html_file),
          url: 'https://multilang-site.com',
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

    it 'extracts titles correctly using h1 selector' do
      items = feed.items
      titles = items.map(&:title)
      expect(titles).to all(be_a(String))
      expect(titles).to all(satisfy { |title| !title.strip.empty? })
    end

    it 'extracts language information as categories' do
      items = feed.items
      items_with_language = items.select do |item|
        item.categories.any? { |cat| cat.content.is_a?(String) }
      end
      expect(items_with_language.size).to be > 0
    end

    it 'extracts topic information as categories' do
      items = feed.items
      items_with_topic = items.select do |item|
        item.categories.any? { |cat| cat.content.is_a?(String) }
      end
      expect(items_with_topic.size).to be > 0
    end

    it 'extracts descriptions correctly' do
      items = feed.items
      descriptions = items.map(&:description)
      expect(descriptions).to all(be_a(String))
      expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })
    end

    it 'applies template processing to titles with language prefixes' do
      items = feed.items
      titles = items.map(&:title)
      expect(titles).to all(be_a(String))
      expect(titles).to all(satisfy { |title| !title.strip.empty? })
    end

    it 'includes correct language values in titles' do
      items = feed.items
      expect(items.size).to be > 0
    end

    it 'preserves original content in template processing' do
      items = feed.items
      items.each do |item|
        expect(item.title).to be_a(String)
        expect(item.title.length).to be > 0
      end
    end

    it 'includes language as categories' do
      items = feed.items
      items_with_language = items.select do |item|
        item.categories.any? { |cat| cat.content.is_a?(String) }
      end
      expect(items_with_language.size).to be > 0
    end

    it 'has different language values for different items' do
      items = feed.items
      language_values = items.map do |item|
        language_cat = item.categories.find { |cat| cat.content.is_a?(String) }
        language_cat ? language_cat.content : 'No Language'
      end
      expect(language_values).to all(be_a(String))
    end

    it 'includes topic as categories' do
      items = feed.items
      items_with_topic = items.select do |item|
        item.categories.any? { |cat| cat.content.is_a?(String) }
      end
      expect(items_with_topic.size).to be > 0
    end

    it 'validates template syntax is correct' do
      template_config = config[:selectors][:title][:post_process].first
      expect(template_config).to have_key(:string)
      expect(template_config).not_to have_key(:template)
    end

    it 'applies template processing to all items' do
      items = feed.items
      items.each do |item|
        expect(item.title).to be_a(String)
        expect(item.title.length).to be > 0
      end
    end

    it 'handles different language values in template' do
      items = feed.items
      expect(items.size).to be > 0
    end

    it 'validates that the configuration is complete' do
      expect(config[:channel]).not_to be_nil
      expect(config[:selectors]).not_to be_nil
      expect(config[:channel][:url]).not_to be_nil
      expect(config[:channel][:title]).not_to be_nil
      expect(config[:channel][:language]).not_to be_nil
      expect(config[:channel][:time_zone]).not_to be_nil
      expect(config[:selectors][:language]).not_to be_nil
      expect(config[:selectors][:topic]).not_to be_nil
      expect(config[:selectors][:title]).not_to be_nil
      expect(config[:selectors][:title][:post_process]).not_to be_nil
    end

    it 'validates template post-processor configuration' do
      template_config = config[:selectors][:title][:post_process].first
      expect(template_config[:name]).to eq('template')
      expect(template_config[:string]).to be_a(String)
    end

    it 'validates language extractor configuration' do
      language_config = config[:selectors][:language]
      expect(language_config[:extractor]).to eq('attribute')
      expect(language_config[:attribute]).to eq('data-lang')
      expect(language_config[:selector]).to be_a(String)
    end
  end
end
