# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource do
  subject(:instance) { described_class.new(response, config, request_config:) }

  let(:config) { described_class::DEFAULT_CONFIG }
  let(:request_config) { { strategy: :faraday, headers: request_headers } }
  let(:response) { build_response(body:, headers: response_headers, url:) }
  let(:url) { Html2rss::Url.from_relative('https://example.com', 'https://example.com') }
  let(:body) { build_html_with_article('Article 1 Title', '/article1') }

  def build_response(body:, headers:, url:)
    Html2rss::RequestService::Response.new(body:, headers:, url:)
  end

  def build_html_with_article(title, link, head_markup: '', extra_body: '')
    article_id = title.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')

    <<~HTML
      <html>
        <head>
          #{head_markup}
        </head>
        <body>
          <article id="#{article_id}">
            <h2>#{title} <!-- remove this --></h2>
            <a href="#{link}">Read more</a>
          </article>
          #{extra_body}
        </body>
      </html>
    HTML
  end

  def request_headers = { 'User-Agent' => 'RSpec' }

  def response_headers = { 'content-type': 'text/html' }

  def build_custom_config(overrides = {})
    described_class::DEFAULT_CONFIG.merge(overrides) do |_key, old_val, new_val|
      old_val.is_a?(Hash) && new_val.is_a?(Hash) ? old_val.merge(new_val) : new_val
    end
  end

  def stub_next_page(path, title, link: '/article2', extra_body: '')
    next_url = Html2rss::Url.from_relative(path, url)
    next_body = build_html_with_article(title, link, extra_body:)
    next_response = build_response(body: next_body, headers: response_headers, url: next_url)

    allow(Html2rss::RequestService).to receive(:execute).and_return(next_response)
    next_url
  end

  def article_titles
    instance.articles.map(&:title)
  end

  def expect_titles_and_request_count(expected_url, *expected_titles)
    expect(article_titles).to match_array(expected_titles)
    expect(Html2rss::RequestService).to have_received(:execute)
      .with(an_object_having_attributes(url: expected_url, headers: request_headers), strategy: :faraday)
      .once
  end

  def pagination_back_markup
    '<nav class="pagination"><a href="/">Back</a></nav>'
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
      custom = described_class::DEFAULT_CONFIG.merge(
        scraper: described_class::DEFAULT_CONFIG[:scraper].merge(json_state: { enabled: false })
      )

      expect(described_class::Config.call(custom)).to be_success
    end

    it 'accepts pagination overrides' do
      custom = described_class::DEFAULT_CONFIG.merge(pagination: { enabled: false, max_pages: 2 })

      expect(described_class::Config.call(custom)).to be_success
    end
  end

  describe '#articles' do
    before do
      allow(Parallel).to receive(:map) do |enum, *_args, &block|
        enum.to_a.map { |item| block.call(item) }
      end
      allow(Parallel).to receive(:worker_number).and_return(0)
    end

    context 'with a single page' do
      it 'returns only articles from the initial response', :aggregate_failures do
        allow(Html2rss::RequestService).to receive(:execute)

        articles = instance.articles

        expect(Html2rss::RequestService).not_to have_received(:execute)
        expect(articles.map(&:title)).to contain_exactly('Article 1 Title')
      end
    end

    context 'when link rel="next" is present' do
      let(:config) { build_custom_config(pagination: { max_pages: 2 }) }
      let(:body) do
        build_html_with_article(
          'Article 1 Title',
          '/article1',
          head_markup: '<link rel="next" href="/page/2" />'
        )
      end

      it 'fetches the next page and merges articles before cleanup', :aggregate_failures do
        next_url = stub_next_page('https://example.com/page/2', 'Article 2 Title')

        expect_titles_and_request_count(next_url, 'Article 1 Title', 'Article 2 Title')
      end
    end

    context 'when pagination links loop back' do
      let(:config) { build_custom_config(pagination: { max_pages: 3 }) }
      let(:body) do
        build_html_with_article(
          'Article 1 Title',
          '/article1',
          extra_body: '<nav class="pagination"><a href="/page/2">More</a></nav>'
        )
      end

      it 'avoids refetching visited pages', :aggregate_failures do
        next_url = stub_next_page('https://example.com/page/2', 'Article 2 Title', extra_body: pagination_back_markup)

        expect_titles_and_request_count(next_url, 'Article 1 Title', 'Article 2 Title')
      end
    end

    context 'when no scrapers are found' do
      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:from).and_raise(Html2rss::AutoSource::Scraper::NoScraperFound)
        allow(Html2rss::Log).to receive(:warn)
      end

      it 'returns an empty array and logs a warning', :aggregate_failures do
        expect(instance.articles).to eq []
        expect(Html2rss::Log).to have_received(:warn).with(/No auto source scraper found/)
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

    context 'when scraper discovery raises an error' do
      before do
        allow(Html2rss::AutoSource::Scraper).to receive(:from).and_raise(StandardError, 'Test error')
      end

      it 'propagates the error' do
        expect { instance.articles }.to raise_error(StandardError, 'Test error')
      end
    end
  end

  describe '#initialize' do
    it 'sets instance variables correctly', :aggregate_failures do
      expect(instance.instance_variable_get(:@parsed_body)).to eq response.parsed_body
      expect(instance.instance_variable_get(:@url)).to eq response.url
      expect(instance.instance_variable_get(:@opts)).to eq described_class::DEFAULT_CONFIG
      expect(instance.instance_variable_get(:@request_strategy)).to eq(:faraday)
      expect(instance.instance_variable_get(:@request_headers)).to eq(request_headers)
    end

    context 'with custom options' do
      let(:config) { build_custom_config(scraper: { schema: { enabled: false } }) }

      it 'uses the provided options' do
        expect(instance.instance_variable_get(:@opts)).to eq config
      end
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
