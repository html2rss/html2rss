# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::RssFeedDetector do
  subject(:instance) { described_class.new(parsed_body, url:) }

  let(:url) { 'https://example.com' }
  let(:parsed_body) { Html2rss::HtmlParser.parse_html(html) }

  describe '.articles?' do
    context 'when RSS feed links are present' do
      let(:html) do
        <<~HTML
          <html>
            <head>
              <link rel="alternate" type="application/rss+xml" href="/feed.xml" title="RSS Feed">
            </head>
            <body></body>
          </html>
        HTML
      end

      it 'returns true' do
        expect(described_class.articles?(parsed_body)).to be true
      end
    end

    context 'when no RSS feed links are present' do
      let(:html) do
        <<~HTML
          <html>
            <head>
              <link rel="stylesheet" href="/style.css">
            </head>
            <body></body>
          </html>
        HTML
      end

      it 'returns false' do
        expect(described_class.articles?(parsed_body)).to be false
      end
    end

    context 'when parsed_body is nil' do
      it 'returns false' do
        expect(described_class.articles?(nil)).to be false
      end
    end
  end

  describe '#each' do
    context 'when RSS feed links are present' do
      let(:html) do
        <<~HTML
          <html>
            <head>
              <title>Test Blog</title>
              <link rel="alternate" type="application/rss+xml" href="/feed.xml" title="Main RSS Feed">
              <link rel="alternate" type="application/rss+xml" href="/comments.xml" title="Comments Feed">
            </head>
            <body></body>
          </html>
        HTML
      end

      let(:html_with_xss) do
        <<~HTML
          <html>
            <head>
              <title>Test Blog</title>
              <link rel="alternate" type="application/rss+xml" href="/feed.xml" title="<script>alert('xss')</script>RSS Feed">
            </head>
            <body></body>
          </html>
        HTML
      end

      it 'yields the correct number of articles' do
        articles = instance.each.to_a
        expect(articles.size).to eq 2
      end

      it 'yields articles with correct title' do
        articles = instance.each.to_a
        first_article = articles.first

        expect(first_article[:title]).to eq 'Main RSS Feed'
      end

      it 'yields articles with correct URL' do
        articles = instance.each.to_a
        first_article = articles.first

        expect(first_article[:url].to_s).to eq 'https://example.com/feed.xml'
      end

      it 'yields articles with helpful description containing clickable link' do
        articles = instance.each.to_a
        first_article = articles.first

        expect(first_article[:description]).to include 'https://example.com/feed.xml'
      end

      it 'yields articles with clickable link in description', :aggregate_failures do
        first_article = instance.each.first

        expect(first_article[:description]).to include '<a href="https://example.com/feed.xml"'
        expect(first_article[:description]).to include('>Main RSS Feed</a>')
        expect(first_article[:description]).to include('rel="nofollow noopener noreferrer"')
        expect(first_article[:description]).to include('target="_blank"')
      end

      it 'yields articles with correct categories' do
        articles = instance.each.to_a
        first_article = articles.first

        expect(first_article[:categories]).to include 'feed', 'auto-detected', 'rss'
      end

      it 'yields articles with correct scraper' do
        articles = instance.each.to_a
        first_article = articles.first

        expect(first_article[:scraper]).to eq described_class
      end

      it 'yields articles with monthly rotating ID' do
        articles = instance.each.to_a
        first_article = articles.first
        current_month = Time.now.strftime('%Y-%m')

        expect(first_article[:id]).to match(/^rss-feed-\d+-#{current_month}$/)
      end

      it 'generates different IDs for different months' do
        allow(Time).to receive(:now).and_return(Time.new(2024, 1, 15))
        jan_id = instance.each.to_a.first[:id]

        allow(Time).to receive(:now).and_return(Time.new(2024, 2, 15))
        feb_id = instance.each.to_a.first[:id]

        expect(jan_id).not_to eq(feb_id)
      end

      it 'includes month in January ID' do
        allow(Time).to receive(:now).and_return(Time.new(2024, 1, 15))
        articles = instance.each.to_a
        jan_id = articles.first[:id]

        expect(jan_id).to include('2024-01')
      end

      it 'includes month in February ID' do
        allow(Time).to receive(:now).and_return(Time.new(2024, 2, 15))
        articles = instance.each.to_a
        feb_id = articles.first[:id]

        expect(feb_id).to include('2024-02')
      end

      it 'yields articles with author information' do
        articles = instance.each.to_a
        first_article = articles.first

        expect(first_article[:author]).to eq 'Test Blog'
      end

      it 'sanitizes HTML in feed titles for security', :aggregate_failures do
        xss_instance = described_class.new(Html2rss::HtmlParser.parse_html(html_with_xss), url:)
        first_article = xss_instance.first

        expect(first_article[:description]).to include 'RSS Feed'
        expect(first_article[:description]).not_to include '<script>'
        expect(first_article[:description]).not_to include 'alert('
      end

      it 'yields articles for all RSS feeds' do
        articles = instance.each.to_a
        second_article = articles.last

        expect(second_article[:title]).to eq 'Comments Feed'
      end

      it 'yields articles with correct URLs for all feeds' do
        articles = instance.each.to_a
        second_article = articles.last

        expect(second_article[:url].to_s).to eq 'https://example.com/comments.xml'
      end
    end

    context 'when different feed types are present' do
      let(:html) do
        <<~HTML
          <html>
            <head>
              <title>Test Site</title>
              <link rel="alternate" type="application/rss+xml" href="/feed.xml" title="Main RSS Feed">
              <link rel="alternate" type="application/atom+xml" href="/atom.xml" title="Atom News Feed">
              <link rel="alternate" type="application/json" href="/feed.json" title="JSON Data Feed">
            </head>
            <body></body>
          </html>
        HTML
      end

      it 'detects different feed types correctly' do
        articles = instance.each.to_a

        expect(articles.size).to eq 3
      end

      it 'categorizes RSS feeds correctly' do
        articles = instance.each.to_a
        rss_article = articles.find { |a| a[:url].to_s.include?('feed.xml') }

        expect(rss_article[:categories]).to include 'rss'
      end

      it 'categorizes Atom feeds correctly' do
        articles = instance.each.to_a
        atom_article = articles.find { |a| a[:url].to_s.include?('atom.xml') }

        expect(atom_article[:categories]).to include 'atom'
      end

      it 'categorizes JSON feeds correctly' do
        articles = instance.each.to_a
        json_article = articles.find { |a| a[:url].to_s.include?('feed.json') }

        expect(json_article[:categories]).to include 'json-feed'
      end
    end

    context 'when no RSS feed links are present' do
      let(:html) do
        <<~HTML
          <html>
            <head>
              <link rel="stylesheet" href="/style.css">
            </head>
            <body></body>
          </html>
        HTML
      end

      it 'yields nothing' do
        expect(instance.each.to_a).to be_empty
      end
    end

    context 'when RSS feed link has no href' do
      let(:html) do
        <<~HTML
          <html>
            <head>
              <link rel="alternate" type="application/rss+xml" title="Broken Feed">
            </head>
            <body></body>
          </html>
        HTML
      end

      it 'yields nothing' do
        expect(instance.each.to_a).to be_empty
      end
    end
  end
end
