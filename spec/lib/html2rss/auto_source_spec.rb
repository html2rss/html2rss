# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource do
  subject(:instance) { described_class.new(response, config) }

  let(:config) { described_class::DEFAULT_CONFIG }
  let(:response) { build_response(body:, headers:, url:) }
  let(:url) { Addressable::URI.parse('https://example.com') }
  let(:body) { build_html_with_article('Article 1 Title', '/article1') }
  let(:headers) { { 'content-type': 'text/html' } }

  # Test factories for maintainability
  def build_response(body:, headers:, url:)
    Html2rss::RequestService::Response.new(body:, headers:, url:)
  end

  def build_html_with_article(title, link)
    <<~HTML
      <html>
        <body>
          <article id="article-1">
            <h2>#{title} <!-- remove this --></h2>
            <a href="#{link}">Read more</a>
          </article>
        </body>
      </html>
    HTML
  end

  def build_custom_config(overrides = {})
    described_class::DEFAULT_CONFIG.merge(overrides) do |_key, old_val, new_val|
      old_val.is_a?(Hash) && new_val.is_a?(Hash) ? old_val.merge(new_val) : new_val
    end
  end

  def expected_article_data
    {
      title: 'Article 1 Title',
      id: 'article-1',
      guid: '1qmp481',
      description: 'Read more',
      image: nil,
      scraper: Html2rss::AutoSource::Scraper::SemanticHtml
    }
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

    it 'returns an array of articles', :aggregate_failures do
      expect(instance.articles).to be_a(Array)
      expect(instance.articles.size).to eq 1
    end

    it 'returns articles with correct attributes', :aggregate_failures do
      article = instance.articles.first
      expected_url = Addressable::URI.parse('https://example.com/article1')

      expect(article).to be_a(Html2rss::RssBuilder::Article) & have_attributes(expected_article_data)
      expect(article.url).to eq expected_url
    end

    context 'when no scrapers are found' do
      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:from).and_raise(Html2rss::AutoSource::Scraper::NoScraperFound)
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'returns an empty array and logs a warning', :aggregate_failures do
        expect(instance.articles).to eq []
        expect(Html2rss::Log).to have_received(:warn)
          .with(/No auto source scraper found for URL: #{url}. Skipping auto source./)
      end
    end

    context 'with custom configuration' do
      let(:config) do
        build_custom_config(
          scraper: { schema: { enabled: false }, html: { enabled: false } },
          cleanup: { keep_different_domain: true, min_words_title: 5 }
        )
      end

      it 'uses the custom configuration' do
        expect(instance.articles).to be_a(Array)
      end
    end

    context 'when scraper raises an error' do
      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:from).and_raise(StandardError, 'Test error')
      end

      it 'raises the error' do
        expect { instance.articles }.to raise_error(StandardError, 'Test error')
      end
    end
  end

  describe '#initialize' do
    it 'sets instance variables correctly', :aggregate_failures do
      expect(instance.instance_variable_get(:@parsed_body)).to eq response.parsed_body
      expect(instance.instance_variable_get(:@url)).to eq response.url
      expect(instance.instance_variable_get(:@opts)).to eq described_class::DEFAULT_CONFIG
    end

    context 'with custom options' do
      let(:config) { build_custom_config(scraper: { schema: { enabled: false } }) }

      it 'uses custom options' do
        expect(instance.instance_variable_get(:@opts)).to eq config
      end
    end
  end

  describe 'private methods' do
    describe '#extract_articles' do
      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:from).and_return([Html2rss::AutoSource::Scraper::SemanticHtml])
        scraper_instance = instance_double(Html2rss::AutoSource::Scraper::SemanticHtml, each: [])
        allow(Html2rss::AutoSource::Scraper::SemanticHtml).to receive(:new).and_return(scraper_instance)
        allow(Html2rss::AutoSource::Cleanup).to receive(:call)
      end

      it 'calls scrapers and cleanup' do
        instance.send(:extract_articles)
        expect(Html2rss::AutoSource::Cleanup).to have_received(:call)
      end
    end

    describe '#run_scraper' do
      before do
        allow(Parallel).to receive(:map).and_yield({ title: 'Test' }).and_return([instance_double(Object)])
        allow(Html2rss::RssBuilder::Article).to receive(:new)
        allow(Html2rss::Log).to receive(:debug)
      end

      it 'processes articles in parallel', :aggregate_failures do
        scraper_instance = double('TestScraper', class: 'TestScraper', each: [{ title: 'Test' }]) # rubocop:disable RSpec/VerifiedDoubles
        instance.send(:run_scraper, scraper_instance)
        expect(Parallel).to have_received(:map)
        expect(Html2rss::Log).to have_received(:debug)
      end
    end
  end
end
