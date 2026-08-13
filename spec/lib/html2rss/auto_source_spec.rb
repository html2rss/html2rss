# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers

RSpec.describe Html2rss::AutoSource do
  subject(:auto_source) { described_class.new(response, config, request_session:) }

  let(:config) { described_class::DEFAULT_CONFIG }
  let(:url) { Html2rss::Url.from_absolute('https://example.com') }
  let(:response) { Html2rss::RequestService::Response.new(body:, headers: { 'content-type' => 'text/html' }, url:) }
  let(:request_session) { nil }
  let(:body) do
    <<~HTML
      <html>
        <body>
          <article id="article-1">
            <h2>Article 1 Title <!-- remove this --></h2>
            <p>This is some teaser content about Article 1.</p>
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

  describe '::SUFFICIENT_ARTICLE_COUNT' do
    it 'stops later tiers after five url+title articles' do
      expect(described_class::SUFFICIENT_ARTICLE_COUNT).to eq(5)
    end
  end

  describe Html2rss::Config::AutoSourceContract do
    subject(:schema) { described_class }

    it 'validates the default config' do
      expect(schema.call(Html2rss::AutoSource::DEFAULT_CONFIG)).to be_success
    end

    it 'allows toggling the json_state scraper' do
      toggled_config = Html2rss::AutoSource::DEFAULT_CONFIG.merge(
        scraper: Html2rss::AutoSource::DEFAULT_CONFIG[:scraper].merge(json_state: { enabled: false })
      )

      expect(schema.call(toggled_config)).to be_success
    end

    it 'allows toggling the wordpress_api scraper' do
      toggled_config = Html2rss::AutoSource::DEFAULT_CONFIG.merge(
        scraper: Html2rss::AutoSource::DEFAULT_CONFIG[:scraper].merge(wordpress_api: { enabled: false })
      )

      expect(schema.call(toggled_config)).to be_success
    end

    it 'allows toggling the microdata scraper' do
      toggled_config = Html2rss::AutoSource::DEFAULT_CONFIG.merge(
        scraper: Html2rss::AutoSource::DEFAULT_CONFIG[:scraper].merge(microdata: { enabled: false })
      )

      expect(schema.call(toggled_config)).to be_success
    end

    describe 'optional(:cleanup)' do
      let(:config) do
        config = Html2rss::AutoSource::DEFAULT_CONFIG.dup
        config[:auto_source] = { cleanup: Html2rss::AutoSource::Cleanup::DEFAULT_CONFIG }
        config
      end

      it 'validates cleanup defaults' do
        expect(schema.call(config)).to be_success
      end
    end
  end

  describe '#articles' do
    subject(:articles) { auto_source.articles }

    describe 'when scraping succeeds' do
      subject(:article) { articles.first }

      it 'returns a single Html2rss::Article', :aggregate_failures do
        expect(articles.size).to eq(1)
        expect(article).to be_a(Html2rss::Article)
      end

      it 'preserves article content', :aggregate_failures do
        expect(article.title).to eq('Article 1 Title')
        expect(article.id).to eq('article-1')
        expect(article.description).to eq('This is some teaser content about Article 1.')
        expect(article.scraper).to eq(Html2rss::AutoSource::Scraper::SemanticHtml)
      end

      it 'sanitizes the article url' do
        expected_url = Html2rss::Url.from_absolute('https://example.com/article1')
        expect(article.url).to eq(expected_url)
      end
    end

    context 'when no scrapers are found' do
      let(:body) { '<html><body></body></html>' }

      before { allow(Html2rss::Log).to receive(:warn) }

      it 'logs a warning and returns an empty array', :aggregate_failures do
        expect(articles).to eq([])
        expect(Html2rss::Log).to have_received(:warn)
          .with(a_string_including("#{described_class}: no scraper matched #{url}"))
      end
    end

    context 'when the response body is empty' do
      let(:body) { '' }

      before { allow(Html2rss::Log).to receive(:warn) }

      it 'returns an empty array without raising' do
        expect(articles).to eq([])
      end
    end

    context 'with custom configuration that disables matching scrapers' do
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          scraper: described_class::DEFAULT_CONFIG[:scraper].transform_values { |cfg| cfg.merge(enabled: false) },
          cleanup: { keep_different_domain: true, min_words_title: 5 }
        )
      end

      before { allow(Html2rss::Log).to receive(:warn) }

      it 'returns no articles when every scraper is disabled' do
        expect(articles).to eq([])
      end
    end

    context 'when structured scrapers already yield enough articles' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          scraper: described_class::DEFAULT_CONFIG[:scraper].transform_values { |cfg| cfg.merge(enabled: false) }
                                                            .merge(schema: { enabled: true })
        )
      end
      let(:schema_articles) do
        Array.new(described_class::SUFFICIENT_ARTICLE_COUNT) do |index|
          {
            id: "schema-#{index}",
            title: "Schema Story #{index} Extra Words Here",
            description: 'summary',
            url: "https://example.com/schema-#{index}"
          }
        end
      end
      let(:schema_instance) do
        instance = instance_double(Html2rss::AutoSource::Scraper::Schema, each: schema_articles.each)
        allow(instance).to receive(:class).and_return(Html2rss::AutoSource::Scraper::Schema)
        instance
      end

      before do
        allow(Html2rss::AutoSource::Scraper::Schema).to receive_messages(
          options_key: :schema,
          articles?: true,
          new: schema_instance
        )
        allow(Html2rss::SST::Normalizer).to receive(:call)
        allow(Html2rss::AutoSource::Scraper::SemanticHtml).to receive(:new)
        allow(Html2rss::AutoSource::Scraper::Html).to receive(:new)
      end

      it 'skips SST and heuristic scrapers', :aggregate_failures do
        expect(articles.size).to eq(described_class::SUFFICIENT_ARTICLE_COUNT)
        expect(Html2rss::SST::Normalizer).not_to have_received(:call)
        expect(Html2rss::AutoSource::Scraper::SemanticHtml).not_to have_received(:new)
        expect(Html2rss::AutoSource::Scraper::Html).not_to have_received(:new)
      end
    end

    context 'when structured articles fail Cleanup title floor' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          scraper: described_class::DEFAULT_CONFIG[:scraper].transform_values { |cfg| cfg.merge(enabled: false) }
                                                            .merge(
                                                              schema: { enabled: true },
                                                              semantic_html: { enabled: true,
                                                                               fallback_anchorless: true }
                                                            )
        )
      end
      let(:schema_articles) do
        Array.new(described_class::SUFFICIENT_ARTICLE_COUNT) do |index|
          {
            id: "thin-#{index}",
            title: 'News',
            description: 'summary',
            url: "https://example.com/thin-#{index}"
          }
        end
      end
      let(:semantic_articles) do
        Array.new(described_class::SUFFICIENT_ARTICLE_COUNT) do |index|
          Html2rss::Article.new(
            id: "sem-#{index}",
            title: "Semantic Story #{index} Extra Words",
            description: 'summary',
            url: "https://example.com/sem-#{index}",
            scraper: Html2rss::AutoSource::Scraper::SemanticHtml
          )
        end
      end
      let(:schema_instance) do
        instance = instance_double(Html2rss::AutoSource::Scraper::Schema, each: schema_articles.each)
        allow(instance).to receive(:class).and_return(Html2rss::AutoSource::Scraper::Schema)
        instance
      end
      let(:semantic_instance) do
        instance_double(Html2rss::AutoSource::Scraper::SemanticHtml, each: semantic_articles.each, extractable?: true)
      end
      let(:document) { instance_double(Html2rss::SST::Document) }

      before do
        allow(Html2rss::AutoSource::Scraper::Schema).to receive_messages(
          options_key: :schema, articles?: true, new: schema_instance
        )
        allow(Html2rss::AutoSource::Scraper).to receive(:normalize_sst).and_return(document)
        allow(Html2rss::AutoSource::Scraper::SemanticHtml).to receive(:new).and_return(semantic_instance)
      end

      it 'continues into heuristics so Cleanup does not empty the feed', :aggregate_failures do
        expect(articles.size).to eq(described_class::SUFFICIENT_ARTICLE_COUNT)
        expect(articles.map(&:title)).to all(include('Semantic Story'))
        expect(Html2rss::AutoSource::Scraper::SemanticHtml).to have_received(:new)
      end
    end

    context 'when SemanticHtml is sufficient before Html' do # rubocop:disable RSpec/MultipleMemoizedHelpers
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          scraper: described_class::DEFAULT_CONFIG[:scraper].transform_values { |cfg| cfg.merge(enabled: false) }
                                                            .merge(
                                                              semantic_html: { enabled: true,
                                                                               fallback_anchorless: true },
                                                              html: {
                                                                enabled: true,
                                                                minimum_selector_frequency: 2,
                                                                use_top_selectors: 5,
                                                                fallback_anchorless: true
                                                              }
                                                            )
        )
      end
      let(:semantic_articles) do
        Array.new(described_class::SUFFICIENT_ARTICLE_COUNT) do |index|
          Html2rss::Article.new(
            id: "sem-#{index}",
            title: "Semantic Story #{index} Extra Words",
            description: 'summary',
            url: "https://example.com/sem-#{index}",
            scraper: Html2rss::AutoSource::Scraper::SemanticHtml
          )
        end
      end
      let(:document) { instance_double(Html2rss::SST::Document) }
      let(:semantic_instance) do
        instance_double(Html2rss::AutoSource::Scraper::SemanticHtml, each: semantic_articles.each, extractable?: true)
      end

      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:normalize_sst).and_return(document)
        allow(Html2rss::AutoSource::Scraper::SemanticHtml).to receive(:new).and_return(semantic_instance)
        allow(Html2rss::AutoSource::Scraper::Html).to receive(:new)
        allow(Html2rss::AutoSource::Cleanup).to receive(:call) { |arts, **| arts }
      end

      it 'does not instantiate Html when SemanticHtml is sufficient', :aggregate_failures do
        expect(articles.size).to eq(described_class::SUFFICIENT_ARTICLE_COUNT)
        expect(Html2rss::AutoSource::Scraper::Html).not_to have_received(:new)
      end
    end

    context 'with microdata-only content' do
      subject(:article) { articles.first }

      let(:body) do
        <<~HTML
          <html>
            <body>
              <article itemscope itemtype="https://schema.org/NewsArticle" itemid="story-1">
                <h1 itemprop="headline">Microdata only story</h1>
                <a itemprop="url" href="/microdata-only-story">Read more</a>
                <p itemprop="description">Short summary.</p>
              </article>
            </body>
          </html>
        HTML
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          scraper: {
            schema: { enabled: false },
            microdata: { enabled: true },
            json_state: { enabled: false },
            wordpress_api: { enabled: false },
            sitemap: { enabled: false },
            microformats2: { enabled: false },
            meta_oembed: { enabled: false },
            semantic_html: { enabled: false },
            html: {
              enabled: false,
              minimum_selector_frequency: described_class::DEFAULT_CONFIG.dig(:scraper, :html,
                                                                              :minimum_selector_frequency),
              use_top_selectors: described_class::DEFAULT_CONFIG.dig(:scraper, :html, :use_top_selectors)
            }
          }
        )
      end

      it 'returns Article objects from the Microdata scraper', :aggregate_failures do
        expect(articles.size).to eq(1)
        expect(article.title).to eq('Microdata only story')
        expect(article.id).to eq('story-1')
        expect(article.url.to_s).to eq('https://example.com/microdata-only-story')
        expect(article.scraper).to eq(Html2rss::AutoSource::Scraper::Microdata)
      end
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
