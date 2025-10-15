# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource do
  subject(:auto_source) { described_class.new(response, config) }

  let(:config) { described_class::DEFAULT_CONFIG }
  let(:url) { Html2rss::Url.from_relative('https://example.com', 'https://example.com') }
  let(:headers) { { 'content-type': 'text/html' } }
  let(:body) do
    <<~HTML
      <html>
        <body>
          <article id="article-1">
            <h2>Article 1 Title <!-- remove this --></h2>
            <a href="/article1">Read more</a>
          </article>
        </body>
      </html>
    HTML
  end
  let(:response) do
    Html2rss::RequestService::Response.new(body:, headers:, url:)
  end

  describe '::DEFAULT_CONFIG' do
    it 'is a frozen Hash' do
      expect(described_class::DEFAULT_CONFIG).to be_a(Hash) & be_frozen
    end
  end

  describe '::Config' do
    it 'validates default config' do
      expect(described_class::Config.call(described_class::DEFAULT_CONFIG)).to be_success
    end

    it 'allows toggling the json_state scraper' do
      config = described_class::DEFAULT_CONFIG.merge(
        scraper: described_class::DEFAULT_CONFIG[:scraper].merge(json_state: { enabled: false })
      )

      expect(described_class::Config.call(config)).to be_success
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
      allow(Parallel).to receive(:flat_map).and_wrap_original do |_original, scrapers, **_kwargs, &block|
        scrapers.flat_map(&block)
      end
    end

    it 'returns an array of articles', :aggregate_failures do
      expect(auto_source.articles).to be_a(Array)
      expect(auto_source.articles.size).to eq 1
    end

    it 'wraps scraped data in articles' do
      expect(auto_source.articles.first).to be_a(Html2rss::RssBuilder::Article)
    end

    it 'keeps the article title' do
      expect(auto_source.articles.first.title).to eq('Article 1 Title')
    end

    it 'derives an id from the markup' do
      expect(auto_source.articles.first.id).to eq('article-1')
    end

    it 'keeps the description content' do
      expect(auto_source.articles.first.description).to include('Read more')
    end

    it 'records the scraper class' do
      expect(auto_source.articles.first.scraper).to eq(Html2rss::AutoSource::Scraper::SemanticHtml)
    end

    it 'sanitizes the url' do
      expected_url = Html2rss::Url.from_relative('https://example.com/article1', 'https://example.com')
      expect(auto_source.articles.first.url).to eq(expected_url)
    end

    context 'when no scrapers are found' do
      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:from).and_raise(Html2rss::AutoSource::Scraper::NoScraperFound)
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'returns an empty array and logs a warning', :aggregate_failures do
        expect(auto_source.articles).to eq []
        expect(Html2rss::Log).to have_received(:warn)
          .with(/No auto source scraper found for URL: #{url}. Skipping auto source./)
      end
    end

    context 'with custom configuration' do
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          scraper: { schema: { enabled: false }, html: { enabled: false } },
          cleanup: { keep_different_domain: true, min_words_title: 5 }
        ) { |_key, old_val, new_val| old_val.is_a?(Hash) ? old_val.merge(new_val) : new_val }
      end

      it 'uses the custom configuration' do
        expect(auto_source.articles).to be_a(Array)
      end
    end

    context 'when multiple scrapers emit overlapping articles' do
      before do
        scrapers = [
          [
            {
              id: 'shared-first',
              title: 'Shared Article Title',
              description: 'Same url',
              url: 'https://example.com/shared'
            },
            {
              id: 'first-only',
              title: 'First Exclusive Story',
              description: 'Only first',
              url: 'https://example.com/first'
            }
          ],
          [
            {
              id: 'shared-second',
              title: 'Shared Article Title',
              description: 'Same url',
              url: 'https://example.com/shared'
            },
            {
              id: 'second-only',
              title: 'Second Exclusive Story',
              description: 'Only second',
              url: 'https://example.com/second'
            }
          ]
        ].map do |articles|
          Class.new do
            articles_for_scraper = articles

            define_singleton_method(:options_key) { :semantic_html }

            define_method(:initialize) { |_parsed_body, url:, **_options| @url = url }

            define_method(:each) { articles_for_scraper }
          end
        end

        allow(Html2rss::AutoSource::Scraper).to receive(:from).and_return(scrapers)
        allow(Html2rss::AutoSource::Cleanup).to receive(:call) do |articles, **|
          articles.uniq { |article| article.url.to_s }
        end
      end

      it 'deduplicates aggregated articles by url' do
        expect(auto_source.articles.map { |article| article.url.to_s }).to match_array(
          %w[https://example.com/shared https://example.com/first https://example.com/second]
        )
      end
    end

    context 'when scraper raises an error' do
      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:from).and_raise(StandardError, 'Test error')
      end

      it 'raises the error' do
        expect { auto_source.articles }.to raise_error(StandardError, 'Test error')
      end
    end
  end
end
