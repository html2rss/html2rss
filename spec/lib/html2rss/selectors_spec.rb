# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors do
  subject(:instance) { described_class.new(response, selectors:, time_zone:) }

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

  describe 'default items selector' do
    let(:body) do
      <<~HTML
        <html><body>
          <a href="/posts/real">Real story</a>
          <a href="#">Top</a>
          <a href="javascript:void(0)">Popup</a>
          <a href="mailto:ed@example.com">Email</a>
        </body></html>
      HTML
    end

    context 'when the items selector is the default spelling' do
      let(:selectors) { { items: { selector: described_class::DEFAULT_ITEMS_SELECTOR, enhance: false } } }

      it 'admits only the permalink, not junk-scheme anchors' do
        expect(instance.articles.map { |article| article.url.to_s }).to eq(['http://example.com/posts/real'])
      end
    end

    context 'when the items selector is blank' do
      let(:selectors) { { items: { selector: '   ', enhance: false } } }

      it 'expands like the default and drops junk-scheme anchors' do
        expect(instance.articles.map { |article| article.url.to_s }).to eq(['http://example.com/posts/real'])
      end
    end

    context 'when the items selector is an explicit a' do
      let(:selectors) { { items: { selector: 'a', enhance: false } } }

      it 'still admits junk-scheme anchors', :aggregate_failures do
        urls = instance.articles.filter_map { |article| article.url&.to_s }

        expect(instance.articles.size).to eq(4)
        expect(urls).to include('http://example.com/posts/real', 'mailto:ed@example.com')
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

    context 'when selectors include pagination metadata' do
      before { selectors[:items][:pagination] = { max_pages: 3 } }

      it 'still extracts only from the current response' do
        expect(titles).to eq(%w[article1 article2])
      end
    end
  end

  describe '#each' do
    it 'returns an Enumerator if no block is given' do
      expect(instance.each).to be_a(Enumerator)
    end

    it 'yields the articles to given block' do
      expect { |b| instance.each(&b) }.to yield_successive_args(
        Html2rss::Article,
        Html2rss::Article
      )
    end
  end

  describe 'article extraction' do
    context 'when title is static and description the html of <body>' do
      # Issue was reported at: https://github.com/html2rss/html2rss/issues/157
      let(:selectors) do
        {
          items: { selector: 'html' },
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
        expect(instance.articles.first).to have_attributes(
          title: 'Test string',
          description: "<body>\n  <main>\n    <h1>article1</h1>\n    <script>alert('');</script>\n  </main>\n</body>"
        )
      end
    end

    context 'when the page exposes relative item links' do
      let(:selectors) do
        {
          items: { selector: 'article' },
          title: { selector: 'h1' },
          url: { selector: 'a', extractor: 'href' }
        }
      end
      let(:body) do
        <<~HTML
          <html><body><article><h1>article1</h1><a href="article1">Read</a></article></body></html>
        HTML
      end

      it 'resolves item links against the current page url' do
        expect(instance.articles.map { |article| article.url.to_s }).to eq(['http://example.com/article1'])
      end
    end

    context 'when items selector is an anchor element and url selector is omitted' do
      let(:selectors) do
        {
          items: { selector: 'a.card', enhance: false },
          title: { selector: 'h3' }
        }
      end
      let(:body) do
        <<~HTML
          <html><body>
            <a class="card" href="/posts/first"><h3>First Post</h3></a>
            <a class="card" href="/posts/second"><h3>Second Post</h3></a>
          </body></html>
        HTML
      end

      it 'automatically extracts the url from the anchor href attribute', :aggregate_failures do
        urls = instance.articles.map { |article| article.url.to_s }
        expect(urls).to eq(%w[http://example.com/posts/first http://example.com/posts/second])
      end
    end

    context 'when an enclosure selector is configured' do
      let(:selectors) do
        {
          items: { selector: 'article', enhance: false },
          title: { selector: 'h1' },
          enclosure: {
            selector: 'audio',
            extractor: 'attribute',
            attribute: 'src',
            content_type: 'audio/mpeg'
          }
        }
      end
      let(:body) do
        <<~HTML
          <html><body>
            <article>
              <h1>episode</h1>
              <audio src="/media/episode.mp3"></audio>
              <img src="/media/cover.jpg" alt="cover">
            </article>
          </body></html>
        HTML
      end

      it 'maps selector :enclosure onto Article :enclosures', :aggregate_failures do
        article = instance.articles.first

        expect(article.enclosures.size).to eq(1)
        expect(article.enclosures.first.url.to_s).to eq('http://example.com/media/episode.mp3')
        expect(article.enclosures.first.type).to eq('audio/mpeg')
      end
    end
  end

  describe '#each_enhance_pair' do
    before { selectors[:items][:enhance] = true }

    it 'enhances empty baselines with semantic extraction', :aggregate_failures do
      baseline, enhanced, = instance.each_enhance_pair.first

      expect(baseline).to include(:title)
      expect(enhanced).to include(:title, :url)
    end

    context 'when selector/key is already present in the baseline' do
      let(:selectors) do
        {
          items: { selector: 'article', enhance: true },
          title: { extractor: 'static', static: 'Selected Article1 Headline' }
        }
      end

      it 'does not override the existing value' do
        _baseline, enhanced, = instance.each_enhance_pair.first
        expect(enhanced[:title]).to eq('Selected Article1 Headline')
      end
    end

    context 'when extractor returns nil' do
      before do
        allow(Html2rss::Html::ArticleExtractor).to receive(:call).and_return(nil)
      end

      it 'returns the baseline unchanged' do
        baseline, enhanced, = instance.each_enhance_pair.first
        expect(enhanced).to eq(baseline)
      end
    end

    context 'when the container has no anchor tag' do
      let(:body) do
        <<~HTML
          <html><body><article><h1>No Link Article</h1><p>Teaser text</p></article></body></html>
        HTML
      end

      it 'enhances the article_hash anchorlessly', :aggregate_failures do
        _baseline, enhanced, = instance.each_enhance_pair.first
        expect(enhanced[:title]).to eq('No Link Article')
        expect(enhanced[:url].to_s).to eq('http://example.com/#no-link-article')
      end

      it 'omits fields the extractor could not fill instead of storing nil' do
        _baseline, enhanced, = instance.each_enhance_pair.first

        expect(enhanced.compact).to eq(enhanced)
      end
    end

    context 'when the item is an anchor with an empty href' do
      let(:selectors) { { items: { selector: 'a.card', enhance: true }, title: { selector: 'h3' } } }
      let(:body) { '<html><body><a class="card" href=""><h3>Empty Href Title</h3></a></body></html>' }

      it 'fills the url that the baseline left nil' do
        _baseline, enhanced, = instance.each_enhance_pair.first

        expect(enhanced[:url]).not_to be_nil
      end
    end

    context 'when all enhanceable fields are already extracted' do
      let(:selectors) do
        {
          items: { selector: 'article', enhance: true },
          title: { extractor: 'static', static: 'Selected title' },
          url: { extractor: 'static', static: 'https://example.com/selected' },
          description: { extractor: 'static', static: 'Selected description' },
          published_at: { extractor: 'static', static: 'Mon, 01 Jul 2019 12:00:00 +0000' },
          enclosure: { extractor: 'static', static: 'https://example.com/file.mp3', content_type: 'audio/mpeg' },
          categories: %i[category],
          category: { extractor: 'static', static: 'News' }
        }
      end

      it 'does not call ArticleExtractor and keeps the baseline', :aggregate_failures do
        allow(Html2rss::Html::ArticleExtractor).to receive(:call)

        _baseline, enhanced, = instance.each_enhance_pair.first

        expect(Html2rss::Html::ArticleExtractor).not_to have_received(:call)
        expect(enhanced).to include(:title, :url, :description)
      end
    end

    context 'when leftover contains a naive date' do
      let(:time_zone) { 'Europe/Berlin' }
      let(:body) do
        <<~HTML
          <html><body>
            <article>
              <h1>Dated leftover article</h1>
              <a href="/article1">More</a>
              <span>12 March 2024</span>
            </article>
          </body></html>
        HTML
      end

      it 'localizes leftover dates with the channel time_zone', :aggregate_failures do
        _baseline, enhanced, = instance.each_enhance_pair.first
        expect(enhanced[:published_at]).to be_a(DateTime)
        expect(enhanced[:published_at].zone).to eq('+01:00')
      end
    end
  end

  describe '#select' do
    subject(:value) { instance.select(:title, item) }

    let(:item) { Nokogiri::HTML(body).at('article:first') }

    it 'returns the selected value' do
      expect(value).to eq('article1')
    end

    context 'when selecting :url on an anchor element without an explicit url selector' do
      subject(:value) { instance.select(:url, item).to_s }

      let(:item) { Nokogiri::HTML(body).at('a') }
      let(:body) { '<html><body><a href="/target">Item</a></body></html>' }

      it 'extracts and resolves the url directly from the item element' do
        expect(value).to eq('http://example.com/target')
      end
    end

    context 'when name is not a referencing a selector' do
      subject(:value) { instance.select(:unknown, item) }

      it 'raises an error' do
        expect { value }.to raise_error(described_class::InvalidSelectorName, "Selector for 'unknown' is not defined.")
      end
    end

    context 'when a template nested select resolves relative urls' do
      subject(:value) do
        instance.select(:title, item, base_url: 'https://other.example/section/').to_s
      end

      let(:selectors) do
        {
          items: { selector: 'article' },
          path: { selector: 'a', extractor: 'href' },
          title: {
            selector: 'h1',
            # rubocop:disable-next Style/FormatStringToken -- template post-processor uses %{key}
            post_process: { name: 'template', string: '%{path}' }
          }
        }
      end
      let(:body) do
        <<~HTML
          <html><body><article><h1>Title</h1><a href="/item">x</a></article></body></html>
        HTML
      end

      it 'honors the per-call base_url for nested template selects' do
        expect(value).to eq('https://other.example/item')
      end
    end

    context 'when selecting categories' do
      let(:item) { Nokogiri::HTML(body).at('article') }
      let(:body) do
        <<~HTML
          <html><body>
            <article>
              <span class="category">News</span>
              <div class="tags"><a href="/t/ruby">Ruby</a><a href="/t/rss">RSS</a></div>
            </article>
          </body></html>
        HTML
      end

      # rubocop:disable-next RSpec/ExampleLength
      it 'flattens single- and multi-node category selectors into discrete strings' do
        selectors.merge!(
          category: { selector: '.category' },
          tags: { selector: '.tags a', extractor: 'text' },
          categories: %i[category tags]
        )

        expect(instance.select(:categories, item)).to eq(%w[News Ruby RSS])
      end

      it 'returns an empty list when a referenced category selector is missing' do
        selectors[:categories] = %i[missing]

        expect(instance.select(:categories, item)).to eq([])
      end

      # rubocop:disable-next RSpec/ExampleLength
      it 'applies post_process steps on multi-node category extracts' do
        selectors.merge!(
          tags: {
            selector: '.tags a',
            extractor: 'text',
            post_process: { name: 'gsub', pattern: 'R', replacement: 'r' }
          },
          categories: %i[tags]
        )

        expect(instance.select(:categories, item)).to eq(%w[ruby rSS])
      end
    end

    context 'when a multi-node category selector yields blank text' do
      subject(:categories) { instance.select(:categories, item) }

      let(:item) { Nokogiri::HTML(body).at('article') }
      let(:body) do
        '<html><body><article><div class="tags">' \
          '<a href="/t/ruby">Ruby</a><a href="/t/blank"> </a></div></article></body></html>'
      end
      let(:selectors) do
        { items: { selector: 'article', enhance: false }, tags: { selector: '.tags a' }, categories: %i[tags] }
      end

      it 'keeps only the non-blank category text' do
        expect(categories).to eq(%w[Ruby])
      end
    end

    context 'when a multi-node category selector extracts hrefs' do
      subject(:categories) { instance.select(:categories, item) }

      let(:item) { Nokogiri::HTML(body).at('article') }
      let(:body) do
        '<html><body><article><div class="tags">' \
          '<a href="/t/ruby">Ruby</a><a href="/t/rss">RSS</a></div></article></body></html>'
      end
      let(:selectors) do
        {
          items: { selector: 'article', enhance: false },
          tags: { selector: '.tags a', extractor: 'href' },
          categories: %i[tags]
        }
      end

      it 'returns each resolved url as a string' do
        expect(categories).to eq(['http://example.com/t/ruby', 'http://example.com/t/rss'])
      end
    end

    context 'when a multi-node category selector yields raw static values' do
      subject(:categories) { instance.select(:categories, item) }

      let(:item) { Nokogiri::HTML(body).at('article') }
      let(:body) do
        '<html><body><article><div class="tags">' \
          '<a href="/t/ruby">Ruby</a><a href="/t/rss">RSS</a></div></article></body></html>'
      end
      let(:selectors) do
        {
          items: { selector: 'article', enhance: false },
          tags: { selector: '.tags a', extractor: 'static', static: [' News ', nil, ' ', 42, 'Tech '] },
          categories: %i[tags]
        }
      end

      it 'trims each value, drops nil and blank entries, and stringifies the rest' do
        expect(categories).to eq(%w[News 42 Tech News 42 Tech])
      end
    end

    context 'when category selectors are not backed by matched nodes' do
      subject(:categories) { instance.select(:categories, item) }

      let(:item) { Nokogiri::HTML(body).at('article') }
      let(:body) { '<html><body><article><h1>x</h1></article></body></html>' }
      let(:selectors) do
        {
          items: { selector: 'article', enhance: false },
          fallback: { selector: '.nomatch', extractor: 'static', static: 'Fallback' },
          listed: { extractor: 'static', static: %w[A B] },
          categories: %i[fallback listed]
        }
      end

      it 'keeps the configured static values as-is' do
        expect(categories).to eq(%w[Fallback A B])
      end
    end

    context 'when selecting a guid from another selector' do
      subject(:value) { instance.select(:guid, item) }

      let(:item) { Nokogiri::HTML(body).at('article:first') }
      let(:selectors) { { items: { selector: 'article', enhance: false }, title: { selector: 'h1' }, guid: %i[title] } }

      it 'returns the referenced values as a list' do
        expect(value).to eq(%w[article1])
      end
    end

    context 'when selecting an enclosure' do
      subject(:value) { instance.select(:enclosure, item) }

      let(:item) { Nokogiri::HTML(body).at('article') }
      let(:body) { '<html><body><article><h1>x</h1><a href="/a.mp3">mp3</a></article></body></html>' }
      let(:selectors) do
        {
          items: { selector: 'article', enhance: false },
          enclosure: { selector: 'a', extractor: 'href', content_type: 'audio/mpeg' }
        }
      end

      it 'resolves the url and carries the configured content type', :aggregate_failures do
        expect(value[:url].to_s).to eq('http://example.com/a.mp3')
        expect(value[:type]).to eq('audio/mpeg')
      end

      it 'returns nil when the enclosure value is blank' do
        selectors[:enclosure] = { extractor: 'static', static: ' ' }

        expect(value).to be_nil
      end
    end
  end

  describe '#select with post_process steps' do
    let(:item) { Nokogiri::HTML(body).at('article:first') }

    it 'applies a single post_process step to the extracted value' do
      selectors[:title] = { selector: 'h1', post_process: { name: 'gsub', pattern: 'article', replacement: 'post' } }

      expect(instance.select(:title, item)).to eq('post1')
    end

    it 'lets a post_process step follow the href extractor' do
      selectors[:link] = {
        selector: 'a', extractor: 'href', post_process: { name: 'gsub', pattern: 'article', replacement: 'post' }
      }

      expect(instance.select(:link, item)).to eq('http://example.com/post1')
    end

    it 'applies an array of post_process steps in order' do # rubocop:disable RSpec/ExampleLength
      selectors[:title] = {
        selector: 'h1',
        post_process: [
          { name: 'gsub', pattern: 'article', replacement: 'A' },
          { name: 'gsub', pattern: '1', replacement: '9' }
        ]
      }

      expect(instance.select(:title, item)).to eq('A9')
    end

    it 'rejects an unknown post_process name when the selectors are compiled', :aggregate_failures do
      selectors[:title] = { selector: 'h1', post_process: { name: 'nope' } }

      expect { instance }
        .to raise_error(described_class::PostProcessors::UnknownPostProcessorName, "Unknown name 'nope'")
    end
  end

  describe '#select :url resolution' do
    subject(:value) { instance.select(:url, item) }

    let(:item) { Nokogiri::HTML(body).at('article') }
    let(:body) { '<html><body><article><h1>T</h1><a href="/item">x</a></article></body></html>' }

    it 'prefers a configured url selector over the anchor fallback' do
      selectors[:url] = { selector: 'a', extractor: 'href' }

      expect(value.to_s).to eq('http://example.com/item')
    end

    it 'raises for a non-anchor item without a url selector' do
      expect { value }.to raise_error(described_class::InvalidSelectorName, "Selector for 'url' is not defined.")
    end

    it 'falls back to the anchor href when the url selector is explicitly nil' do
      selectors[:url] = nil
      item = Nokogiri::HTML('<html><body><a href="/target">x</a></body></html>').at('a')

      expect(instance.select(:url, item).to_s).to eq('http://example.com/target')
    end

    it 'raises for a configured-as-nil selector that is not url' do
      selectors[:title] = nil

      expect { instance.select(:title, item) }
        .to raise_error(described_class::InvalidSelectorName, "Selector for 'title' is not defined.")
    end
  end

  describe '#each enhancement' do
    let(:body) do
      '<html><body><article><h1>Big Title</h1><p>Some description text here.</p>' \
        '<a href="/post">Read more</a></article></body></html>'
    end

    it 'fills missing fields from the article when enhance is on', :aggregate_failures do
      selectors[:items][:enhance] = true
      article = instance.articles.first

      expect(article.title).to eq('Big Title')
      expect(article.url.to_s).to eq('http://example.com/post')
      expect(article.description).to eq('Some description text here.')
    end

    it 'leaves unselected fields empty when enhance is off', :aggregate_failures do
      selectors[:items][:enhance] = false
      article = instance.articles.first

      expect(article.title).to eq('Big Title')
      expect(article.url.to_s).to be_empty
      expect(article.description).to be_nil
    end
  end

  describe 'post_process option validation' do
    it 'rejects a post-process step that lacks a required option' do
      selectors[:title] = { selector: 'h1', post_process: { name: 'gsub' } }

      expect { instance }
        .to raise_error(described_class::PostProcessors::MissingOption, /The `pattern` option is missing/)
    end
  end

  describe 'JSON responses' do
    let(:response) do
      Html2rss::RequestService::Response.new(
        url: 'http://example.com',
        headers: { 'content-type': 'application/json' },
        body: '{"items":[{"title":"A"},{"title":"B"}]}'
      )
    end
    let(:selectors) { { items: { selector: 'object array object', enhance: false }, title: { selector: 'title' } } }

    it 'extracts articles from the XML view of the document' do
      expect(instance.articles.map(&:title)).to eq(%w[A B])
    end
  end

  describe '#selector_config_for' do
    it 'returns the key and config for a defined selector, string or symbol', :aggregate_failures do
      expect(instance.selector_config_for(:title)).to eq([:title, { selector: 'h1' }])
      expect(instance.selector_config_for('title')).to eq([:title, { selector: 'h1' }])
    end

    it 'returns a nil config for an undefined selector only when allow_nil is given', :aggregate_failures do
      expect(instance.selector_config_for(:missing, allow_nil: true)).to eq([:missing, nil])
      expect { instance.selector_config_for(:missing) }
        .to raise_error(described_class::InvalidSelectorName, "Selector for 'missing' is not defined.")
    end
  end

  describe '#select reserved names' do
    it 'rejects the items key as an attribute selector' do
      expect { instance.select(:items, Nokogiri::HTML(body).at('article')) }
        .to raise_error(described_class::InvalidSelectorName, "Attribute selector 'items' is reserved for items.")
    end
  end
end
