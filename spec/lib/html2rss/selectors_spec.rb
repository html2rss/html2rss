# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors do
  subject(:instance) { described_class.new(response, selectors: selectors, time_zone: time_zone) }

  let(:response) { Html2rss::RequestService::Response.new url: 'http://example.com', headers: { 'content-type': 'text/html' }, body: }
  let(:selectors) do
    {
      items: { selector: 'article' },
      title: { selector: 'h1' }
    }
  end

  let(:time_zone) { 'UTC' }
  let(:body) do
    <<~HTML
      <html><body>
        <article><h1>article1</h1><a href="/article1">More</a></article>
        <article><h1>article2</h1><a href="/article2">More</a></article>
      </body></html>
    HTML
  end

  describe '#initialize' do
    it 'raises an error if the URL and link selectors are both present' do
      selectors[:link] = {}
      selectors[:url] = {}

      expect { instance }.to raise_error(described_class::InvalidSelectorName, /either use "url" or "link"/)
    end

    context 'when attribute is renamed' do
      before do
        allow(Html2rss::Log).to receive(:warn)
        selectors[:pubDate] = selectors.delete(:published_at)
      end

      it 'handles renamed attributes', :aggregate_failures do
        expect(instance.instance_variable_get(:@selectors)).to include(:published_at)
        expect(Html2rss::Log).to have_received(:warn).with(/deprecated. Please rename to `published_at`./)
      end
    end
  end

  describe '#articles' do
    subject(:titles) { instance.articles.map(&:title) }

    it 'returns the articles' do
      expect(titles).to eq(%w[article1 article2])
    end

    context 'when the order is set to reverse' do
      before { selectors[:items][:order] = 'reverse' }

      it 'reverses the articles' do
        expect(titles).to eq(%w[article2 article1])
      end
    end
  end

  describe '#each' do
    it 'returns an Enumerator if no block is given' do
      expect(instance.each).to be_a(Enumerator)
    end

    it 'yields the articles to given block' do
      expect { |b| instance.each(&b) }.to yield_successive_args(
        Html2rss::RssBuilder::Article,
        Html2rss::RssBuilder::Article
      )
    end
  end

  describe '#extract_article(item)' do
    subject(:article) { instance.extract_article(item) }

    let(:item) { Nokogiri::HTML(body).at('html') }

    context 'when title is static and description the html of <body>' do
      # Issue was reported at: https://github.com/html2rss/html2rss/issues/157
      let(:selectors) do
        {
          title: { extractor: 'static', static: 'Test string' },
          description: { extractor: 'html', selector: 'body' }
        }
      end

      let(:body) do
        <<~HTML
          <html><body>
            <main>
              <h1>article1</h1>
              <script>alert('');</script>
            </main>
          </body></html>
        HTML
      end

      it 'yields the articles with the static title and the <body> as description' do
        expect(instance.extract_article(item)).to a_hash_including(
          title: 'Test string',
          description: "<body>\n  <main>\n    <h1>article1</h1>\n    <script>alert('');</script>\n  </main>\n</body>"
        )
      end
    end
  end

  describe '#enhance_article_hash(article_hash, item)' do
    subject(:enhanced_article) do
      item = Nokogiri::HTML(body).at('article:first')

      instance.enhance_article_hash(article_hash, item)
    end

    before { selectors[:items][:enhance] = true }

    let(:article_hash) { {} }

    it 'enhances the article_hash' do
      expect(enhanced_article).to be(article_hash) & include(:title, :url)
    end

    context 'when selector/key is already present in article_hash' do
      let(:article_hash) { { title: 'Selected Article1 Headline' } }

      it 'does not override the existing value' do
        expect(enhanced_article[:title]).to eq(article_hash[:title])
      end
    end

    context 'when extractor returns nil' do
      before do
        extractor = Html2rss::AutoSource::Scraper::SemanticHtml::Extractor

        allow(extractor).to receive(:new).and_return(instance_double(extractor, call: nil))
      end

      it 'returns article_hash' do
        expect(enhanced_article).to be(article_hash)
      end
    end
  end

  describe '#select' do
    subject(:value) { instance.select(:title, item) }

    let(:item) { Nokogiri::HTML(body).at('article:first') }

    it 'returns the selected value' do
      expect(value).to eq('article1')
    end

    context 'when name is not known' do
      subject(:value) { instance.select(:unknown, item) }

      it 'raises an error' do
        expect { value }.to raise_error(described_class::InvalidSelectorName, /`unknown` is not defined/)
      end
    end
  end
end
