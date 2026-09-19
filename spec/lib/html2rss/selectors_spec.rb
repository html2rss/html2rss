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

      it 'does not call ArticleExtractor' do
        allow(Html2rss::Html::ArticleExtractor).to receive(:call)

        instance.each_enhance_pair.to_a

        expect(Html2rss::Html::ArticleExtractor).not_to have_received(:call)
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
  end
end
