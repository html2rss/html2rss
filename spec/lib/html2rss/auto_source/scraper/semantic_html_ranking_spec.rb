# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::SemanticHtml do
  describe '#each' do
    subject(:new) { described_class.new(parsed_body, url: 'https://page.com') }

    let(:parsed_body) { Nokogiri::HTML.parse(File.read('spec/fixtures/multi_link_block.html')) }
    let(:articles) { new.each.to_a }
    let(:articles_by_url) do
      articles.to_h { |article| [article[:url].to_s, article] }
    end
    let(:excluded_urls) do
      %w[
        https://page.com/category/news
        https://page.com/article/1#comments
        https://twitter.com/share?url=...
        https://page.com/about
        https://page.com/contact
        https://page.com/newsletter/signup
        https://page.com/gallery/3
        https://page.com/author/jane
        https://page.com/newsletter/4
      ]
    end

    it 'prefers the intended content links', :aggregate_failures do
      expect(articles_by_url.fetch('https://page.com/article/1')[:title]).to eq('Main Article Title')
      expect(articles_by_url.fetch('https://page.com/article/3')[:title]).to eq('Correct Title Link')
      expect(articles_by_url.fetch('https://page.com/article/4')[:title]).to eq('Actual Article Text')
    end

    it 'suppresses utility and duplicate link variants' do
      expect(articles_by_url.keys).to contain_exactly(
        'https://page.com/article/1',
        'https://page.com/article/3',
        'https://page.com/article/4'
      )
    end

    it 'drops non-content links from noisy blocks' do
      expect(articles_by_url).not_to include(*excluded_urls)
    end
  end

  describe 'chrome suppression' do
    subject(:articles_by_url) do
      scraper = described_class.new(parsed_body, url: 'https://page.com')
      scraper.each.to_a.to_h { |article| [article[:url].to_s, article] }
    end

    let(:parsed_body) do
      Nokogiri::HTML.parse(<<~HTML)
        <html>
          <body>
            <section class="newsroom-list">
              <nav class="section-nav">
                <a href="/news">View all news</a>
                <a href="/recommended">Recommended for you</a>
              </nav>
              <article>
                <h2><a href="/news/launch-update">Launch update</a></h2>
                <p>Release notes and product changes.</p>
              </article>
            </section>
          </body>
        </html>
      HTML
    end

    it 'keeps content links while excluding common nav chrome' do
      expect(articles_by_url.keys).to contain_exactly('https://page.com/news/launch-update')
    end
  end
end
