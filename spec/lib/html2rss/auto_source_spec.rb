# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource do
  subject(:instance) { described_class.new(response) }

  let(:response) do
    Html2rss::RequestService::Response.new body:, headers:, url:
  end

  let(:url) { Addressable::URI.parse('https://example.com') }
  let(:body) do
    '<html>
      <body>
        <article id="article-1">
          <h2>Article 1 Title <!-- remove this --></h2>
          <a href="/article1">Read more</a>
        </article>
        </body>
    </html>'
  end

  let(:headers) { { 'content-type': 'text/html' } }

  describe '::DEFAULT_CONFIG' do
    it 'is a frozen Hash' do
      expect(described_class::DEFAULT_CONFIG).to be_a(Hash) & be_frozen
    end
  end

  describe '::Config' do
    it 'validates default config' do
      expect(described_class::Config.call(described_class::DEFAULT_CONFIG)).to be_success
    end

    describe 'optional(:cleanup)' do
      let(:config) do
        config = described_class::DEFAULT_CONFIG.dup
        config[:auto_source] = { cleanup: described_class::Cleanup::DEFAULT_CONFIG }
        config
      end

      it 'validates cleanup default config' do
        expect(described_class::Config.call(config)).to be_success
      end
    end
  end

  describe '#articles' do
    before do
      allow(Parallel).to receive(:flat_map)
        .and_yield(Html2rss::AutoSource::Scraper::SemanticHtml.new(response.parsed_body, url:).each)
    end

    let(:article_without_url) do
      { title: 'Article 1 Title',
        id: 'article-1',
        guid: '1aq3b9l',
        description: 'Read more',
        image: nil,
        scraper: Html2rss::AutoSource::Scraper::SemanticHtml }
    end

    let(:url) { Addressable::URI.parse('https://example.com/article1') }

    it 'returns a list of articles', :aggregate_failures do
      expect(instance.articles).to be_a(Array)
      expect(instance.articles.size).to eq 1

      article = instance.articles.first
      expect(article).to be_a(Html2rss::RssBuilder::Article) & have_attributes(article_without_url)
      expect(article.url).to eq url
    end

    context 'when no scrapers are found' do
      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:from).and_raise(Html2rss::AutoSource::Scraper::NoScraperFound)
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'returns an empty array and logs a warning', :aggregate_failures do
        expect(instance.articles).to eq []
        expect(Html2rss::Log).to have_received(:warn)
          .with('No auto source scraper found for the provided URL. Skipping auto source.')
      end
    end
  end
end
