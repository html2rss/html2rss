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

  describe '::DEFAULT_LIMIT' do
    it 'defaults to twenty-five articles' do
      expect(described_class::DEFAULT_LIMIT).to eq(25)
    end
  end

  describe Html2rss::Config::AutoSourceContract do
    subject(:schema) { described_class }

    it 'validates the default config' do
      expect(schema.call(Html2rss::AutoSource::DEFAULT_CONFIG)).to be_success
    end

    it 'allows overriding limit' do
      toggled_config = Html2rss::AutoSource::DEFAULT_CONFIG.merge(limit: 10)

      expect(schema.call(toggled_config)).to be_success
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

    context 'when structured scrapers already yield enough articles' do
      let(:schema_items) do
        Array.new(5) do |index|
          {
            '@type' => 'NewsArticle',
            'headline' => "Schema Story #{index} Extra Words Here",
            'url' => "https://example.com/schema-#{index}",
            'description' => 'summary'
          }
        end
      end
      let(:body) do
        ld = { '@context' => 'https://schema.org', '@type' => 'ItemList', 'itemListElement' => schema_items }
        <<~HTML
          <html><body>
            <script type="application/ld+json">#{ld.to_json}</script>
            <article><h2><a href="/sem-0">Semantic Story 0 Extra Words</a></h2><p>teaser</p></article>
          </body></html>
        HTML
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          limit: 5,
          scraper: described_class::DEFAULT_CONFIG[:scraper].merge(
            microdata: { enabled: false },
            microformats2: { enabled: false },
            json_state: { enabled: false },
            wordpress_api: { enabled: false },
            sitemap: { enabled: false },
            meta_oembed: { enabled: false }
          )
        )
      end

      it 'keeps Schema articles and skips heuristic titles', :aggregate_failures do
        expect(articles.size).to eq(5)
        expect(articles.map(&:title)).to all(include('Schema Story'))
        expect(articles.map(&:scraper)).to all(eq(Html2rss::AutoSource::Scraper::Schema))
        expect(articles.map(&:url).map(&:to_s)).to eq(
          Array.new(5) { |index| "https://example.com/schema-#{index}" }
        )
      end
    end

    context 'when structured articles fail Cleanup title floor' do
      let(:schema_items) do
        Array.new(5) do |index|
          {
            '@type' => 'NewsArticle',
            'headline' => 'News',
            'url' => "https://example.com/thin-#{index}",
            'description' => 'summary'
          }
        end
      end
      let(:body) do
        ld = { '@context' => 'https://schema.org', '@type' => 'ItemList', 'itemListElement' => schema_items }
        semantic = Array.new(5) do |index|
          <<~HTML
            <article>
              <h2><a href="/sem-#{index}">Semantic Story #{index} Extra Words</a></h2>
              <p>This is teaser content about the story.</p>
            </article>
          HTML
        end.join
        <<~HTML
          <html><body>
            <script type="application/ld+json">#{ld.to_json}</script>
            #{semantic}
          </body></html>
        HTML
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          limit: 5,
          scraper: described_class::DEFAULT_CONFIG[:scraper].merge(
            microdata: { enabled: false },
            microformats2: { enabled: false },
            json_state: { enabled: false },
            wordpress_api: { enabled: false },
            sitemap: { enabled: false },
            meta_oembed: { enabled: false },
            html: described_class::DEFAULT_CONFIG[:scraper][:html].merge(enabled: false)
          )
        )
      end

      it 'continues into heuristics so Cleanup does not empty the feed', :aggregate_failures do
        expect(articles.size).to eq(5)
        expect(articles.map(&:title)).to all(include('Semantic Story'))
        expect(articles.map(&:scraper)).to all(eq(Html2rss::AutoSource::Scraper::SemanticHtml))
      end
    end

    context 'when SemanticHtml is sufficient before Html' do
      let(:body) do
        Array.new(5) do |index|
          <<~HTML
            <article id="a#{index}">
              <h2><a href="/sem-#{index}">Semantic Story #{index} Extra Words</a></h2>
              <p>This is teaser content about the story number #{index}.</p>
            </article>
          HTML
        end.join.then { |articles_html| "<html><body>#{articles_html}</body></html>" }
      end
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          limit: 5,
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

      it 'satisfies the limit from SemanticHtml without Html articles', :aggregate_failures do
        expect(articles.size).to eq(5)
        expect(articles.map(&:title)).to all(include('Semantic Story'))
        expect(articles.map(&:scraper)).to all(eq(Html2rss::AutoSource::Scraper::SemanticHtml))
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
