# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dynamic Content Site Configuration' do
  subject(:feed) do
    # Mock the request service to return our HTML fixture
    mock_request_service_with_html_fixture('dynamic_content_site', 'https://example.com/news')

    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples dynamic_content_site.yml]) }
  let(:html_file) { File.join(%w[spec examples dynamic_content_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  let(:items) { feed.items }

  it 'generates a valid RSS feed', :aggregate_failures do
    expect(feed).to be_a(RSS::Rss)
    expect(feed.channel.title).to eq('ACME Dynamic Content Site News')
    expect(feed.channel.link).to eq('https://example.com/news')
  end

  it 'extracts all 6 articles from the dynamic content', :aggregate_failures do
    expect(feed.items).to be_an(Array)
    expect(feed.items.size).to eq(6)
  end

  it 'extracts titles correctly from dynamic content', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    titles = items.map(&:title)
    expect(titles).to all(be_a(String)).and all(satisfy { |title| !title.strip.empty? })
    expect(titles).to include('ACME Corp\'s Revolutionary AI Breakthrough Changes Everything',
                              'ACME Corp\'s Green Coding Summit Reaches Historic Agreement',
                              'ACME Corp\'s Space Exploration Mission Discovers New Planet',
                              'ACME Corp\'s Medical Breakthrough Offers Hope for Bug Patients',
                              'ACME Corp\'s Renewable Energy Reaches New Milestone',
                              'ACME Corp\'s Cybersecurity Threats Reach All-Time High')
  end

  it 'extracts URLs correctly from dynamic content', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    urls = items.map(&:link)
    expect(urls).to all(be_a(String)).and all(satisfy { |url| !url.strip.empty? })
    expect(urls).to include('https://example.com/articles/ai-breakthrough-2024',
                            'https://example.com/articles/climate-summit-2024',
                            'https://example.com/articles/space-mission-discovery',
                            'https://example.com/articles/cancer-treatment-breakthrough',
                            'https://example.com/articles/renewable-energy-milestone',
                            'https://example.com/articles/cybersecurity-threats-2024')
  end

  it 'extracts descriptions correctly with HTML sanitization', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    descriptions = items.map(&:description)
    expect(descriptions).to all(be_a(String)).and all(satisfy { |desc| !desc.strip.empty? }).and all(satisfy { |desc|
      !desc.match(/<[^>]+>/)
    })
    ai_article = items.find { |item| item.title.include?('AI Breakthrough') }
    expect(ai_article.description).to include('ACME Corp scientists have developed', 'artificial intelligence system')
  end

  it 'extracts published dates correctly from timestamps', :aggregate_failures do
    items_with_time = items.select(&:pubDate)
    expect(items_with_time.size).to eq(6)
    expect(items_with_time).to all(have_attributes(pubDate: be_a(Time).and(have_attributes(year: 2024))))
  end

  it 'handles dynamic content loading with browserless strategy', :aggregate_failures do
    expect(config[:strategy]).to eq('browserless')
    expect(items.size).to eq(6)
    expect(items).to all(have_attributes(title: be_a(String)))
    expect(items).to all(have_attributes(description: be_a(String)))
    expect(items).to all(have_attributes(pubDate: be_a(Time)))
  end

  it 'validates that .article-card selector works correctly', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    doc = Nokogiri::HTML(File.read(html_file))
    article_cards = doc.css('.article-card')
    expect(article_cards.size).to eq(6)
    card_titles = article_cards.filter_map { |card| card.at('h2')&.text }
    expect(card_titles).to include('ACME Corp\'s Revolutionary AI Breakthrough Changes Everything',
                                   'ACME Corp\'s Green Coding Summit Reaches Historic Agreement',
                                   'ACME Corp\'s Space Exploration Mission Discovers New Planet')
  end

  it 'handles content that would normally be hidden by JavaScript', :aggregate_failures do
    expect(items).to all(have_attributes(title: be_a(String), description: be_a(String), link: be_a(String)))
    expect(items.size).to eq(6)
  end

  it 'validates that excerpt content is properly extracted and sanitized', :aggregate_failures do
    items.each do |item|
      # Excerpt should be extracted from .excerpt class
      expect(item.description).to be_a(String)
      expect(item.description.length).to be > 50

      # Should contain ACME Corp references
      expect(item.description).to include('ACME Corp')
    end
  end

  it 'handles timestamp parsing from various formats', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    items_with_time = items.select(&:pubDate)
    expect(items_with_time.size).to eq(6)
    expect(items_with_time).to all(have_attributes(pubDate: be_a(Time).and(have_attributes(
                                                                             year: 2024,
                                                                             month: be_between(1, 12),
                                                                             day: be_between(1, 31)
                                                                           ))))
  end
end
