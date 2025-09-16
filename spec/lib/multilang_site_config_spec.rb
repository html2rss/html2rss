# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Multi-Language Site Configuration' do
  let(:config_file) { File.join(%w[spec fixtures multilang-site.test.yml]) }
  let(:html_file) { File.join(%w[spec fixtures multilang-site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  describe 'configuration loading' do
    it 'loads the configuration correctly' do
      expect(config).to be_a(Hash)
      expect(config[:channel][:url]).to eq('https://multilang-site.com')
      expect(config[:channel][:title]).to eq('Multi-Language Site News')
      expect(config[:channel][:language]).to eq('en')
      expect(config[:channel][:time_zone]).to eq('UTC')
      expect(config[:selectors][:items][:selector]).to eq('.post')
      expect(config[:selectors][:title][:selector]).to eq('h1')
      expect(config[:selectors][:language][:selector]).to eq('.lang')
      expect(config[:selectors][:language][:extractor]).to eq('attribute')
      expect(config[:selectors][:language][:attribute]).to eq('data-lang')
      expect(config[:selectors][:description][:selector]).to eq('.content')
      expect(config[:selectors][:topic][:selector]).to eq('.topic')
      expect(config[:selectors][:categories]).to include('language')
      expect(config[:selectors][:categories]).to include('topic')
    end

    it 'has correct post-processing configuration for title' do
      title_post_process = config[:selectors][:title][:post_process]
      expect(title_post_process).to include(
        { name: 'template', string: '[%<language>s] %<self>s' }
      )
    end

    it 'has correct post-processing configuration for description' do
      description_post_process = config[:selectors][:description][:post_process]
      expect(description_post_process).to include(
        { name: 'sanitize_html' }
      )
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
      expect(feed.channel.title).to eq('Multi-Language Site News')
      expect(feed.channel.link).to eq('https://multilang-site.com')
    end

    it 'extracts the correct number of items' do
      expect(feed.items.size).to eq(8)
    end

    describe 'item extraction' do
      let(:items) { feed.items }

      it 'extracts titles correctly using h1 selector' do
        titles = items.map(&:title)
        expect(titles).to all(be_a(String))
        expect(titles).to include('[en] Breaking News: Technology Update')
        expect(titles).to include('[es] Noticias: Actualización Tecnológica')
        expect(titles).to include('[fr] Actualités: Mise à jour technologique')
        expect(titles).to include('[de] Nachrichten: Technologie-Update')
        expect(titles).to include('[en] Environmental Research Update')
        expect(titles).to include('[es] Investigación Ambiental Actualizada')
        expect(titles).to include('[en] Health and Wellness Guide')
        expect(titles).to include('[fr] Guide Santé et Bien-être')
      end

      it 'extracts language information as categories' do
        # All items should have language categories (using data-lang attribute values)
        items_with_language = items.select do |item|
          item.categories.any? do |cat|
            %w[en es fr de].include?(cat.content)
          end
        end
        expect(items_with_language.size).to eq(8) # All 8 items have language

        items_with_language.each do |item|
          expect(item.categories).not_to be_nil
          language_categories = item.categories.select do |cat|
            %w[en es fr de].include?(cat.content)
          end
          expect(language_categories).not_to be_empty
        end
      end

      it 'extracts topic information as categories' do
        # All items should have topic categories
        items_with_topic = items.select do |item|
          item.categories.any? do |cat|
            ['Technology', 'Tecnología', 'Technologie', 'Environment', 'Medio Ambiente', 'Santé',
             'Health'].include?(cat.content)
          end
        end
        expect(items_with_topic.size).to eq(8) # All 8 items have topics

        items_with_topic.each do |item|
          expect(item.categories).not_to be_nil
          topic_categories = item.categories.select do |cat|
            ['Technology', 'Tecnología', 'Technologie', 'Environment', 'Medio Ambiente', 'Santé',
             'Health'].include?(cat.content)
          end
          expect(topic_categories).not_to be_empty
        end
      end

      it 'extracts descriptions correctly' do
        descriptions = items.map(&:description)
        expect(descriptions).to all(be_a(String))
        expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })

        # Check that descriptions contain expected content
        expect(descriptions).to include(match(/quantum computing algorithm/))
        expect(descriptions).to include(match(/algoritmo de computación cuántica/))
        expect(descriptions).to include(match(/algorithme de calcul quantique/))
        expect(descriptions).to include(match(/Quantencomputing-Algorithmus/))
      end
    end

    describe 'multi-language processing with templates' do
      let(:items) { feed.items }

      it 'applies template processing to titles with language prefixes' do
        titles = items.map(&:title)

        # All titles should be strings
        expect(titles).to all(be_a(String))

        # Titles should contain language information from template (using data-lang attribute values)
        expect(titles).to all(match(/^\[(en|es|fr|de)\]/))
      end

      it 'includes correct language values in titles' do
        # Find items by their expected language (using data-lang attribute values)
        english_items = items.select { |item| item.title.start_with?('[en]') }
        spanish_items = items.select { |item| item.title.start_with?('[es]') }
        french_items = items.select { |item| item.title.start_with?('[fr]') }
        german_items = items.select { |item| item.title.start_with?('[de]') }

        expect(english_items.size).to eq(3) # 3 English items
        expect(spanish_items.size).to eq(2) # 2 Spanish items
        expect(french_items.size).to eq(2)  # 2 French items
        expect(german_items.size).to eq(1)  # 1 German item
      end

      it 'preserves original content in template processing' do
        items.each do |item|
          # The title should contain both the language prefix and original content
          expect(item.title).to match(/^\[(en|es|fr|de)\].+/)

          # Should not just be the language, but include the actual title
          expect(item.title.length).to be > 20
        end
      end
    end

    describe 'language-based categorization' do
      let(:items) { feed.items }

      it 'includes language as categories' do
        # All items should have language categories (using data-lang attribute values)
        items_with_language = items.select do |item|
          item.categories.any? do |cat|
            %w[en es fr de].include?(cat.content)
          end
        end
        expect(items_with_language.size).to eq(8) # All 8 items have language

        items_with_language.each do |item|
          expect(item.categories).not_to be_nil
          language_categories = item.categories.select do |cat|
            %w[en es fr de].include?(cat.content)
          end
          expect(language_categories).not_to be_empty
        end
      end

      it 'has different language values for different items' do
        language_values = items.map do |item|
          language_cat = item.categories.find do |cat|
            %w[en es fr de].include?(cat.content)
          end
          language_cat ? language_cat.content : 'No Language'
        end

        expect(language_values).to include('en')
        expect(language_values).to include('es')
        expect(language_values).to include('fr')
        expect(language_values).to include('de')
        expect(language_values).not_to include('No Language')
      end

      it 'includes topic as categories' do
        # All items should have topic categories
        items_with_topic = items.select do |item|
          item.categories.any? do |cat|
            ['Technology', 'Tecnología', 'Technologie', 'Environment', 'Medio Ambiente', 'Santé',
             'Health'].include?(cat.content)
          end
        end
        expect(items_with_topic.size).to eq(8) # All 8 items have topics

        items_with_topic.each do |item|
          expect(item.categories).not_to be_nil
          topic_categories = item.categories.select do |cat|
            ['Technology', 'Tecnología', 'Technologie', 'Environment', 'Medio Ambiente', 'Santé',
             'Health'].include?(cat.content)
          end
          expect(topic_categories).not_to be_empty
        end
      end
    end

    describe 'template post-processing validation' do
      let(:items) { feed.items }

      it 'validates template syntax is correct' do
        # The template should use the correct Ruby string interpolation syntax
        template_config = config[:selectors][:title][:post_process].first
        expect(template_config[:string]).to eq('[%<language>s] %<self>s')
      end

      it 'applies template processing to all items' do
        items.each do |item|
          # Each title should start with a language prefix (using data-lang attribute values)
          expect(item.title).to match(/^\[(en|es|fr|de)\]/)
        end
      end

      it 'handles different language values in template' do
        # Items should have different language prefixes based on their data-lang attribute
        english_items = items.select { |item| item.title.start_with?('[en]') }
        spanish_items = items.select { |item| item.title.start_with?('[es]') }
        french_items = items.select { |item| item.title.start_with?('[fr]') }
        german_items = items.select { |item| item.title.start_with?('[de]') }

        expect(english_items.size).to eq(3)
        expect(spanish_items.size).to eq(2)
        expect(french_items.size).to eq(2)
        expect(german_items.size).to eq(1)
      end
    end

    describe 'configuration issues' do
      it 'identifies the template parameter issue' do
        # The original config had: template: "[%{language}] %{self}"
        # But should be: string: "[%<language>s] %<self>s"
        template_config = config[:selectors][:title][:post_process].first

        # Should use 'string' parameter, not 'template'
        expect(template_config).to have_key(:string)
        expect(template_config).not_to have_key(:template)

        # Should use correct Ruby syntax
        expect(template_config[:string]).to eq('[%<language>s] %<self>s')
      end

      it 'validates that the configuration is complete' do
        # Should have all required sections
        expect(config[:channel]).not_to be_nil
        expect(config[:selectors]).not_to be_nil

        # Should have required channel fields
        expect(config[:channel][:url]).not_to be_nil
        expect(config[:channel][:title]).not_to be_nil
        expect(config[:channel][:language]).not_to be_nil
        expect(config[:channel][:time_zone]).not_to be_nil

        # Should have multi-language selectors
        expect(config[:selectors][:language]).not_to be_nil
        expect(config[:selectors][:topic]).not_to be_nil
        expect(config[:selectors][:title]).not_to be_nil
        expect(config[:selectors][:title][:post_process]).not_to be_nil
      end

      it 'validates template post-processor configuration' do
        template_config = config[:selectors][:title][:post_process].first
        expect(template_config[:name]).to eq('template')
        expect(template_config[:string]).to be_a(String)
        expect(template_config[:string]).to include('%<language>s')
        expect(template_config[:string]).to include('%<self>s')
      end

      it 'validates language extractor configuration' do
        language_config = config[:selectors][:language]
        expect(language_config[:extractor]).to eq('attribute')
        expect(language_config[:attribute]).to eq('data-lang')
        expect(language_config[:selector]).to eq('.lang')
      end
    end
  end
end
