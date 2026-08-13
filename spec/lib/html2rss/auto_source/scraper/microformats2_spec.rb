# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::AutoSource::Scraper::Microformats2 do
  let(:url) { 'https://example.com/blog' }

  describe '.options_key' do
    it { expect(described_class.options_key).to eq(:microformats2) }
  end

  describe '.articles?' do
    context 'when h-entry class is present' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><div class="h-entry"><span class="p-name">Title</span></div></body></html>')
      end

      it { expect(described_class.articles?(parsed_body)).to be true }
    end

    context 'when h-entry is part of multi-class attribute' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><article class="post h-entry custom-card"></article></body></html>')
      end

      it { expect(described_class.articles?(parsed_body)).to be true }
    end

    context 'when h-entry class is absent' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><div class="article">Title</div></body></html>')
      end

      it { expect(described_class.articles?(parsed_body)).to be false }
    end

    context 'when parsed_body is nil' do
      it { expect(described_class.articles?(nil)).to be false }
    end
  end

  describe '#each' do
    subject(:scraper) { described_class.new(parsed_body, url:) }

    context 'when page has h-entry elements with full metadata' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html>
            <body>
              <article class="h-entry">
                <h2 class="p-name">Microformats Post Title</h2>
                <a class="u-url" href="/posts/post-1">Permalink</a>
                <div class="e-content"><p>Full content of entry</p></div>
                <img class="u-featured" src="/images/hero.jpg" alt="Hero">
                <span class="p-author h-card"><span class="p-name">Alice Smith</span></span>
                <time class="dt-published" datetime="2026-08-10T15:00:00Z">August 10, 2026</time>
                <a class="p-category" href="/tag/ruby">Ruby</a>
                <a class="p-category" href="/tag/rss">RSS</a>
              </article>
            </body>
          </html>
        HTML
      end

      let(:expected_article) do
        {
          title: 'Microformats Post Title',
          url: Html2rss::Url.from_absolute('https://example.com/posts/post-1'),
          description: '<p>Full content of entry</p>',
          image: 'https://example.com/images/hero.jpg',
          author: 'Alice Smith',
          published_at: '2026-08-10T15:00:00Z',
          categories: %w[Ruby RSS]
        }
      end

      it 'yields extracted article attributes', :aggregate_failures do
        expect(scraper.to_a).to eq([expected_article])
      end
    end

    context 'when h-entry elements lack title and url' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><div class="h-entry"><span>No metadata</span></div></body></html>')
      end

      it 'yields nothing' do
        expect(scraper.to_a).to be_empty
      end
    end

    context 'when block is not given' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><div class="h-entry"><a class="u-url" href="/1">1</a></div></body></html>')
      end

      it { expect(scraper.each).to be_an(Enumerator) }
    end
  end
end
