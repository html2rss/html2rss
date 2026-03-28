# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers

RSpec.describe Html2rss::AutoSource do
  subject(:auto_source) { described_class.new(response, config, request_session:) }

  let(:config) { described_class::DEFAULT_CONFIG }
  let(:url) { Html2rss::Url.from_absolute('https://example.com') }
  let(:response) { Html2rss::RequestService::Response.new(body:, headers: { 'content-type' => 'text/html' }, url:) }
  let(:request_session) { nil }
  let(:instances_for_arguments) do
    [
      instance_of(Nokogiri::HTML::Document),
      {
        url:,
        request_session: nil,
        opts: hash_including(
          schema: hash_including(enabled: false),
          html: hash_including(enabled: false)
        )
      }
    ]
  end
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

    it 'allows toggling the wordpress_api scraper' do
      toggled_config = described_class::DEFAULT_CONFIG.merge(
        scraper: described_class::DEFAULT_CONFIG[:scraper].merge(wordpress_api: { enabled: false })
      )

      expect(schema.call(toggled_config)).to be_success
    end

    it 'allows toggling the microdata scraper' do
      toggled_config = described_class::DEFAULT_CONFIG.merge(
        scraper: described_class::DEFAULT_CONFIG[:scraper].merge(microdata: { enabled: false })
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
        expected_url = Html2rss::Url.from_absolute('https://example.com/article1')
        expect(article.url).to eq(expected_url)
      end
    end

    context 'when no scrapers are found' do
      before do
        allow(Html2rss::AutoSource::Scraper)
          .to receive(:instances_for)
          .and_raise(Html2rss::AutoSource::Scraper::NoScraperFound, 'no scrapers')
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'logs a warning and returns an empty array', :aggregate_failures do
        expect(articles).to eq([])
        expect(Html2rss::Log).to have_received(:warn)
          .with("#{described_class}: no scraper matched #{url} (no scrapers)")
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
        allow(Html2rss::AutoSource::Scraper).to receive(:instances_for).and_raise(
          Html2rss::AutoSource::Scraper::NoScraperFound, 'No scrapers found for URL.'
        )
        articles
      end

      it 'returns no articles when the custom scraper configuration matches nothing' do
        expect(articles).to eq([])
      end

      it 'passes the overrides to the scraper lookup' do
        expect(Html2rss::AutoSource::Scraper).to have_received(:instances_for).with(*instances_for_arguments)
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
        allow(Html2rss::AutoSource::Scraper)
          .to receive(:instances_for)
          .and_return([semantic_scraper_instance, html_scraper_instance])
        allow(Html2rss::AutoSource::Cleanup).to receive(:call).and_call_original
      end

      it 'deduplicates aggregated articles by url' do
        expect(articles.map { |article| article.url.to_s })
          .to match_array(%w[https://example.com/shared https://example.com/first https://example.com/second])
      end
    end

    context 'when content scrapers and rss feed detector both emit articles' do
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          cleanup: described_class::DEFAULT_CONFIG[:cleanup].merge(min_words_title: 1)
        )
      end
      let(:semantic_scraper_instance) do
        instance_double(
          Html2rss::AutoSource::Scraper::SemanticHtml,
          each: [{ id: 'story-1', title: 'Story number one', url: 'https://example.com/story-1' }].each
        )
      end
      let(:rss_feed_detector_instance) do
        instance_double(
          Html2rss::AutoSource::Scraper::RssFeedDetector,
          each: [{ id: 'feed-1', title: 'Main Site Feed', url: 'https://example.com/feed.xml' }].each
        )
      end

      before do
        allow(semantic_scraper_instance).to receive(:class).and_return(Html2rss::AutoSource::Scraper::SemanticHtml)
        allow(rss_feed_detector_instance).to receive(:class).and_return(Html2rss::AutoSource::Scraper::RssFeedDetector)
        allow(Html2rss::AutoSource::Scraper)
          .to receive(:instances_for)
          .and_return([semantic_scraper_instance, rss_feed_detector_instance])
      end

      it 'keeps content articles and drops feed-discovery entries' do
        expect(articles.map { |article| article.url.to_s }).to contain_exactly('https://example.com/story-1')
      end
    end

    context 'when only rss feed detector emits articles' do
      let(:config) do
        described_class::DEFAULT_CONFIG.merge(
          cleanup: described_class::DEFAULT_CONFIG[:cleanup].merge(min_words_title: 1)
        )
      end
      let(:rss_feed_detector_instance) do
        instance_double(
          Html2rss::AutoSource::Scraper::RssFeedDetector,
          each: [{ id: 'feed-1', title: 'Site Feed', url: 'https://example.com/feed.xml' }].each
        )
      end

      before do
        allow(rss_feed_detector_instance).to receive(:class).and_return(Html2rss::AutoSource::Scraper::RssFeedDetector)
        allow(Html2rss::AutoSource::Scraper)
          .to receive(:instances_for)
          .and_return([rss_feed_detector_instance])
      end

      it 'keeps feed-discovery entries as a fallback surface' do
        expect(articles.map { |article| article.url.to_s }).to contain_exactly('https://example.com/feed.xml')
      end
    end

    context 'when scraper lookup raises an error' do
      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:instances_for).and_raise(StandardError, 'Test error')
      end

      it 're-raises the error' do
        expect { articles }.to raise_error(StandardError, 'Test error')
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
            semantic_html: { enabled: false },
            html: {
              enabled: false,
              minimum_selector_frequency: described_class::DEFAULT_CONFIG.dig(:scraper, :html,
                                                                              :minimum_selector_frequency),
              use_top_selectors: described_class::DEFAULT_CONFIG.dig(:scraper, :html, :use_top_selectors)
            },
            rss_feed_detector: { enabled: false }
          }
        )
      end

      it 'returns RssBuilder::Article objects from the Microdata scraper', :aggregate_failures do
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
