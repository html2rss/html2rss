# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Multi-Language Site Configuration' do
  subject(:feed) do
    # Mock the request service to return our HTML fixture
    mock_request_service_with_html_fixture('multilang_site', 'https://example.com')

    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples multilang_site.yml]) }
  let(:html_file) { File.join(%w[spec examples multilang_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  it 'generates a valid RSS feed', :aggregate_failures do
    expect(feed).to be_a(RSS::Rss)
    expect(feed.channel.title).to eq('ACME Multi-Language Site News')
    expect(feed.channel.link).to eq('https://example.com')
    expect(feed.channel.language).to eq('en')
  end

  it 'extracts all 8 items from the multi-language HTML', :aggregate_failures do
    expect(feed.items).to be_an(Array)
    expect(feed.items.size).to eq(8)
  end

  it 'extracts titles correctly with language template processing', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    titles = items.map(&:title)
    expect(titles).to all(be_a(String)).and all(satisfy { |title| !title.strip.empty? }).and all(match(/^\[[a-z]{2}\]/))
    expect(titles).to include('[en] Breaking News: ACME Corp\'s Technology Update',
                              '[es] Noticias: Actualización Tecnológica de ACME Corp',
                              '[fr] Actualités: Mise à jour technologique d\'ACME Corp',
                              '[de] Nachrichten: ACME Corp Technologie-Update',
                              '[en] Environmental Research Update',
                              '[es] Investigación Ambiental Actualizada',
                              '[en] Health and Wellness Guide',
                              '[fr] Guide Santé et Bien-être')
  end

  it 'extracts language information correctly from data-lang attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    language_categories = items.flat_map(&:categories).select { |cat| cat.content.match?(/^[a-z]{2}$/) }
    expect(language_categories.size).to eq(8)
    language_codes = language_categories.map(&:content)
    expect(language_codes).to include('en', 'es', 'fr', 'de')
    expect(language_codes.count('en')).to eq(3)
    expect(language_codes.count('es')).to eq(2)
    expect(language_codes.count('fr')).to eq(2)
    expect(language_codes.count('de')).to eq(1)
  end

  it 'extracts topic information correctly as categories', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    topic_categories = items.flat_map(&:categories).select do |cat|
      cat.content.match?(/^[A-Za-z\s]+$/) && !cat.content.match?(/^[a-z]{2}$/)
    end
    expect(topic_categories.size).to eq(6)
    topic_names = topic_categories.map(&:content)
    expect(topic_names).to include('Technology', 'Technologie', 'Environment', 'Medio Ambiente', 'Health')
  end

  it 'extracts descriptions correctly with HTML sanitization', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    descriptions = items.map(&:description)
    expect(descriptions).to all(be_a(String)).and all(satisfy { |desc| !desc.strip.empty? }).and all(satisfy { |desc|
      !desc.match(/<[^>]+>/)
    })
    en_article = items.find { |item| item.title.include?('[en] Breaking News') }
    expect(en_article.description).to include('ACME Corp scientists have developed', 'quantum computing algorithm')
    es_article = items.find { |item| item.title.include?('[es] Noticias') }
    expect(es_article.description).to include('Los científicos de ACME Corp han desarrollado',
                                              'algoritmo de computación cuántica')
  end

  it 'validates that template processing works with language interpolation', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    items.each do |item|
      expect(item.title).to match(/^\[[a-z]{2}\]/)
      language_code = item.title.match(/^\[([a-z]{2})\]/)[1]
      language_category = item.categories.find do |cat|
        cat.content == language_code
      end
      expect(language_category).not_to be_nil
    end
  end

  it 'handles multiple languages correctly in the same feed', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items_by_language = feed.items.group_by do |item|
      language_category = item.categories.find { |cat| cat.content.match?(/^[a-z]{2}$/) }
      language_category ? language_category.content : 'unknown'
    end

    expect(items_by_language.keys).to contain_exactly('de', 'en', 'es', 'fr')
    expect(items_by_language.fetch('en').size).to eq(3)
    expect(items_by_language.fetch('es').size).to eq(2)
    expect(items_by_language.fetch('fr').size).to eq(2)
    expect(items_by_language.fetch('de').size).to eq(1)
  end

  it 'validates that attribute extraction works for data-lang', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    items.each do |item|
      language_category = item.categories.find do |cat|
        cat.content.match?(/^[a-z]{2}$/)
      end
      expect(language_category).not_to be_nil
      expect(language_category.content).to match(/^[a-z]{2}$/)
    end
  end

  it 'preserves original content structure in template processing', :aggregate_failures do
    items = feed.items
    expect(items).to all(have_attributes(title: be_a(String).and(satisfy { |title|
      title.length > 10
    }).and(match(/^\[[a-z]{2}\] .+/))))
  end

  it 'handles different topic categories correctly', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items = feed.items
    technology_items = items.select { |item| item.categories.any? { |cat| cat.content.match?(/^[Tt]echnolog/) } }
    expect(technology_items.size).to eq(3)
    environment_items = items.select do |item|
      item.categories.any? do |cat|
        cat.content.match?(/^[Ee]nvironment|^[Mm]edio [Aa]mbiente/)
      end
    end
    expect(environment_items.size).to eq(2)
    health_items = items.select { |item| item.categories.any? { |cat| cat.content.match?(/^[Hh]ealth|^[Ss]anté/) } }
    expect(health_items.size).to eq(2)
  end
end
