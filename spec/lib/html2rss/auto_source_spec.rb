# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource do
  subject(:auto_source) { described_class.new(response, config) }

  let(:config) { described_class::DEFAULT_CONFIG }
  let(:url) { Html2rss::Url.from_relative('https://example.com', 'https://example.com') }
  let(:headers) { { 'content-type': 'text/html' } }
  let(:response) { Html2rss::RequestService::Response.new(body:, headers:, url:) }
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

  describe '::DEFAULT_CONFIG' do
    subject(:default_config) { described_class::DEFAULT_CONFIG }

    it 'is a frozen Hash' do
      expect(default_config).to be_a(Hash).and be_frozen
    end
  end

  describe '::Config' do
    subject(:schema) { described_class::Config }

    it 'validates the default config' do
      expect(schema.call(described_class::DEFAULT_CONFIG)).to be_success
    end

    it 'allows toggling the json_state scraper' do
      toggled_config = described_class::DEFAULT_CONFIG.merge(
        scraper: described_class::DEFAULT_CONFIG[:scraper].merge(json_state: { enabled: false })
      )

      expect(schema.call(toggled_config)).to be_success
    end

    describe 'optional(:cleanup)' do
      let(:config) do
        config = described_class::DEFAULT_CONFIG.dup
        config[:auto_source] = { cleanup: described_class::Cleanup::DEFAULT_CONFIG }
        config
      end

      it 'validates cleanup defaults' do
        expect(schema.call(config)).to be_success
      end
    end
  end

  describe '#articles' do
    subject(:articles) { auto_source.articles }

    before do
      allow(Parallel).to receive(:flat_map).and_wrap_original do |_original, scrapers, **_kwargs, &block|
        scrapers.flat_map(&block)
      end
    end

    describe 'when scraping succeeds' do
      subject(:article) { articles.first }

      it 'returns a single Html2rss::RssBuilder::Article', :aggregate_failures do
        expect(articles.size).to eq(1)
        expect(article).to be_a(Html2rss::RssBuilder::Article)
      end

      it 'preserves article content', :aggregate_failures do
        expect(article.title).to eq('Article 1 Title')
        expect(article.id).to eq('article-1')
        expect(article.description).to include('Read more')
        expect(article.scraper).to eq(Html2rss::AutoSource::Scraper::SemanticHtml)
      end

      it 'sanitizes the article url' do
        expected_url = Html2rss::Url.from_relative('https://example.com/article1', 'https://example.com')
        expect(article.url).to eq(expected_url)
      end
    end

    context 'when no scrapers are found' do
      before do
        allow(Html2rss::AutoSource::Scraper)
          .to receive(:from)
          .and_raise(Html2rss::AutoSource::Scraper::NoScraperFound, 'no scrapers')
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'logs a warning and returns an empty array', :aggregate_failures do
        expect(articles).to eq([])
        expect(Html2rss::Log).to have_received(:warn)
          .with(/No auto source scraper found for URL: #{Regexp.escape(url.to_s)}/)
      end
    end

    context 'with custom configuration' do
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          scraper: { schema: { enabled: false }, html: { enabled: false } },
          cleanup: { keep_different_domain: true, min_words_title: 5 }
        ) { |_key, old_val, new_val| old_val.is_a?(Hash) ? old_val.merge(new_val) : new_val }
      end

      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:from).and_return([])
      end

      it 'passes the overrides to the scraper lookup', :aggregate_failures do
        expect(articles).to eq([])

        expect(Html2rss::AutoSource::Scraper).to have_received(:from)
          .with(instance_of(Nokogiri::HTML::Document),
                hash_including(schema: hash_including(enabled: false),
                               html: hash_including(enabled: false)))
      end
    end

    context 'when multiple scrapers emit overlapping articles' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:first_scraper_articles) do
        [
          { id: 'shared-first', title: 'Shared Article Title', description: 'Same url',
            url: 'https://example.com/shared' },
          { id: 'first-only', title: 'First Exclusive Story', description: 'Only first', url: 'https://example.com/first' }
        ]
      end
      let(:second_scraper_articles) do
        [
          { id: 'shared-second', title: 'Shared Article Title', description: 'Same url',
            url: 'https://example.com/shared' },
          { id: 'second-only', title: 'Second Exclusive Story', description: 'Only second', url: 'https://example.com/second' }
        ]
      end
      let(:semantic_scraper_instance) do
        instance_double(Html2rss::AutoSource::Scraper::SemanticHtml, each: first_scraper_articles.each)
      end
      let(:html_scraper_instance) do
        instance_double(Html2rss::AutoSource::Scraper::Html, each: second_scraper_articles.each)
      end
      let(:semantic_scraper_class) do
        class_double(Html2rss::AutoSource::Scraper::SemanticHtml,
                     options_key: :semantic_html,
                     new: semantic_scraper_instance)
      end
      let(:html_scraper_class) do
        class_double(Html2rss::AutoSource::Scraper::Html,
                     options_key: :html,
                     new: html_scraper_instance)
      end

      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:from).and_return([semantic_scraper_class, html_scraper_class])
        allow(Html2rss::AutoSource::Cleanup).to receive(:call).and_call_original
      end

      it 'deduplicates aggregated articles by url' do
        expect(articles.map { |article| article.url.to_s })
          .to match_array(%w[https://example.com/shared https://example.com/first https://example.com/second])
      end
    end

    context 'when scraper lookup raises an error' do
      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:from).and_raise(StandardError, 'Test error')
      end

      it 're-raises the error' do
        expect { articles }.to raise_error(StandardError, 'Test error')
      end
    end
  end
end
