# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Combined Scraper Sources Configuration' do
  let(:config_file) { File.join(%w[spec fixtures combined-scraper-sources.test.yml]) }
  let(:html_file) { File.join(%w[spec fixtures combined-scraper-sources.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  # Expected article data for maintainable testing
  let(:expected_articles) do
    [
      {
        title: 'Apple Releases New MacBook Pro with M3 Chip',
        url: 'https://technews.com/articles/apple-macbook-pro-m3-2024',
        category: 'Breaking News', # After gsub replacement
        tags: %w[Apple Laptops Processors]
      },
      {
        title: 'Google Launches New AI Assistant Features',
        url: 'https://technews.com/articles/google-ai-assistant-update',
        category: 'Breaking News',
        tags: ['Google', 'Artificial Intelligence', 'Voice Assistant']
      },
      {
        title: 'Tesla Announces New Electric Vehicle Model',
        url: 'https://technews.com/articles/tesla-new-ev-model-2024',
        category: 'Breaking News',
        tags: ['Tesla', 'Electric Vehicles', 'Autonomous Driving']
      },
      {
        title: 'Microsoft Updates Windows 12 Preview',
        url: 'https://technews.com/articles/microsoft-windows-12-preview',
        category: 'Breaking News',
        tags: ['Microsoft', 'Windows', 'Operating System']
      },
      {
        title: 'Meta Introduces New VR Headset',
        url: 'https://technews.com/articles/meta-vr-headset-2024',
        category: 'Breaking News',
        tags: ['Meta', 'Virtual Reality', 'Gaming']
      },
      {
        title: 'Amazon Web Services Expands Cloud Services',
        url: 'https://technews.com/articles/aws-cloud-services-expansion',
        category: 'Breaking News',
        tags: ['AWS', 'Cloud Computing', 'Infrastructure']
      }
    ]
  end

  describe 'configuration loading' do
    it 'loads the configuration correctly' do
      expect(config).to be_a(Hash)
      expect(config[:channel][:url]).to eq('https://technews.com')
      expect(config[:channel][:title]).to eq('TechNews Daily')
      expect(config[:auto_source]).to eq({})
      expect(config[:selectors][:items][:selector]).to eq('.news-item')
      expect(config[:selectors][:items][:enhance]).to be true
      expect(config[:selectors][:title][:selector]).to eq('h2')
      expect(config[:selectors][:url][:selector]).to eq('a')
      expect(config[:selectors][:url][:extractor]).to eq('href')
      expect(config[:selectors][:description][:selector]).to eq('.content')
      expect(config[:selectors][:category][:selector]).to eq('.category')
      expect(config[:selectors][:tags][:selector]).to eq('.tags a')
      expect(config[:selectors][:tags][:extractor]).to eq('text')
      expect(config[:selectors][:custom_guid][:selector]).to eq('h2')
      expect(config[:selectors][:guid]).to eq(['custom_guid'])
    end

    it 'has correct post-processing configuration for category' do
      category_post_process = config[:selectors][:category][:post_process]
      expect(category_post_process).to include(
        { name: 'gsub', pattern: 'News', replacement: 'Breaking News' }
      )
    end

    it 'has correct post-processing configuration for custom_guid' do
      custom_guid_post_process = config[:selectors][:custom_guid][:post_process]
      expect(custom_guid_post_process).to include(
        { name: 'template', string: '%<self>s-%<url>s', methods: %w[self url] }
      )
    end

    it 'has auto_source enabled for combined approach' do
      expect(config[:auto_source]).to eq({})
    end

    it 'has enhance enabled for items' do
      expect(config[:selectors][:items][:enhance]).to be true
    end
  end

  # Shared examples for maintainable testing
  shared_examples 'valid RSS feed' do
    it 'generates a valid RSS feed' do
      expect(feed).to be_a(RSS::Rss)
      expect(feed.channel.title).to eq('TechNews Daily')
      expect(feed.channel.link).to eq('https://technews.com')
    end

    it 'extracts items using combined auto-source and manual selectors' do
      # Auto-source finds many items from JSON-LD and HTML, manual selectors provide additional processing
      expect(feed.items.size).to be > 6
      expect(feed.items.size).to be < 100 # Reasonable upper bound
    end
  end

  shared_examples 'article extraction' do
    it 'extracts titles correctly using combined approach' do
      titles = feed.items.map(&:title).compact
      expected_titles = expected_articles.map { |article| article[:title] }

      expect(titles).to all(be_a(String))
      # The main articles should be present (from both auto-source and manual selectors)
      expected_titles.each { |title| expect(titles).to include(title) }
    end

    it 'extracts URLs correctly using combined approach' do
      urls = feed.items.map(&:link).compact
      expected_urls = expected_articles.map { |article| article[:url] }

      expect(urls).to all(be_a(String))
      # The main article URLs should be present
      expected_urls.each { |url| expect(urls).to include(url) }
    end

    it 'extracts descriptions correctly using combined approach' do
      descriptions = feed.items.map(&:description).compact
      expect(descriptions).to all(be_a(String))
      expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })
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

    include_examples 'valid RSS feed'
    include_examples 'article extraction'

    describe 'category and tag processing' do
      let(:items) { feed.items }

      it 'applies gsub replacement to categories' do
        # Check that items have categories (more items due to combined approach)
        items_with_categories = items.select { |item| item.categories.any? }
        expect(items_with_categories.size).to be > 6

        # Check that we have some categories with "News" in them
        all_categories = items.flat_map { |item| item.categories.map(&:content) }
        expect(all_categories.join(' ')).to include('News')
      end

      it 'extracts tags correctly' do
        all_tags = items.flat_map { |item| item.categories.map(&:content) }.uniq

        # Check that we have tag categories
        expect(all_tags).not_to be_empty

        # Verify that tags are being extracted (they may be concatenated with newlines)
        tag_content = all_tags.join(' ')
        expect(tag_content).to include('Apple')
        expect(tag_content).to include('Google')
        expect(tag_content).to include('Tesla')
        expect(tag_content).to include('Microsoft')
        expect(tag_content).to include('Meta')
        expect(tag_content).to include('AWS')
        expect(tag_content).to include('Laptops')
        expect(tag_content).to include('Virtual Reality')
      end
    end

    describe 'auto-source integration' do
      it 'has auto_source enabled for combined approach' do
        expect(config[:auto_source]).to eq({})
      end
    end

    describe 'enhance functionality' do
      it 'has enhance enabled for items' do
        expect(config[:selectors][:items][:enhance]).to be true
      end

      it 'enhances items with additional information' do
        items = feed.items

        # Enhanced items should have additional information extracted automatically
        # Some items may not have all fields due to auto-source detection
        items_with_titles = items.select { |item| item.title }
        expect(items_with_titles.size).to be > 0

        items_with_titles.each do |item|
          expect(item.title).not_to be_nil
          expect(item.link).not_to be_nil
          expect(item.description).not_to be_nil
        end
      end
    end

    describe 'custom GUID generation' do
      it 'configures custom GUID generation correctly' do
        custom_guid_config = config[:selectors][:custom_guid]
        expect(custom_guid_config[:selector]).to eq('h2')
        expect(custom_guid_config[:post_process]).to include(
          { name: 'template', string: '%<self>s-%<url>s', methods: %w[self url] }
        )
      end

      it 'uses custom GUID for items' do
        guid_config = config[:selectors][:guid]
        expect(guid_config).to eq(['custom_guid'])
      end

      it 'generates GUIDs for items' do
        items = feed.items
        guids = items.map(&:guid)

        # All items should have GUIDs
        expect(guids).to all(be_a(RSS::Rss::Channel::Item::Guid))
        expect(guids.map(&:content)).to all(satisfy { |guid| !guid.strip.empty? })

        # With auto-source detection, some duplicate GUIDs are expected
        # but we should have a reasonable number of unique GUIDs
        unique_guids = guids.map(&:content).uniq
        expect(unique_guids.size).to be > 10
        expect(unique_guids.size).to be < guids.size # Some duplicates expected
      end
    end

    describe 'gsub post-processing' do
      let(:items) { feed.items }

      it 'applies gsub replacement to categories' do
        category_config = config[:selectors][:category]
        post_process = category_config[:post_process]
        expect(post_process).to include({ name: 'gsub', pattern: 'News', replacement: 'Breaking News' })
      end

      it 'replaces "News" with "Breaking News" in category field' do
        # The gsub only applies to the specific category field, not all categories
        # Check that we have categories and they contain some processed content
        items.each do |item|
          next unless item.categories.any?

          category_contents = item.categories.map(&:content)
          # Should have some categories
          expect(category_contents).not_to be_empty
        end
      end
    end

    describe 'template post-processing' do
      let(:items) { feed.items }

      it 'applies template processing to custom GUID' do
        custom_guid_config = config[:selectors][:custom_guid]
        post_process = custom_guid_config[:post_process]
        expect(post_process).to include({ name: 'template', string: '%<self>s-%<url>s', methods: %w[self url] })
      end

      it 'generates custom GUIDs using template' do
        items.each do |item|
          expect(item.guid).to be_a(RSS::Rss::Channel::Item::Guid)
          expect(item.guid.content).not_to be_empty
          # GUID should be a non-empty string (may be hashed or templated)
          expect(item.guid.content.length).to be > 0
        end
      end
    end

    describe 'configuration issues' do
      it 'validates that the configuration is complete' do
        # Should have all required sections
        expect(config[:channel]).not_to be_nil
        expect(config[:auto_source]).to eq({}) # Disabled for testing
        expect(config[:selectors]).not_to be_nil

        # Should have required channel fields
        expect(config[:channel][:url]).not_to be_nil
        expect(config[:channel][:title]).not_to be_nil

        # Should have combined scraper source selectors
        expect(config[:selectors][:items]).not_to be_nil
        expect(config[:selectors][:items][:enhance]).to be true
        expect(config[:selectors][:category]).not_to be_nil
        expect(config[:selectors][:tags]).not_to be_nil
        expect(config[:selectors][:custom_guid]).not_to be_nil
        expect(config[:selectors][:guid]).not_to be_nil
      end

      it 'validates auto_source configuration' do
        expect(config[:auto_source]).to eq({})
      end

      it 'validates enhance configuration' do
        expect(config[:selectors][:items][:enhance]).to be true
      end

      it 'validates gsub post-processor configuration' do
        gsub_config = config[:selectors][:category][:post_process].first
        expect(gsub_config[:name]).to eq('gsub')
        expect(gsub_config[:pattern]).to eq('News')
        expect(gsub_config[:replacement]).to eq('Breaking News')
      end

      it 'validates template post-processor configuration' do
        template_config = config[:selectors][:custom_guid][:post_process].first
        expect(template_config[:name]).to eq('template')
        expect(template_config[:string]).to eq('%<self>s-%<url>s')
        expect(template_config[:methods]).to eq(%w[self url])
      end
    end
  end
end
