# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Capture do
  let(:url) { 'https://example.com/blog' }

  before do
    allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_return(nil)
  end

  describe '#build' do
    it 'asks Syndication::Discovery for native feed preference with a session', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      response = html_response(File.read('spec/fixtures/local_feed_test.html'))
      articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
      stub_outcome(response, articles:)
      feed = Html2rss::Url.from_absolute('https://example.com/feed.xml')
      allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_return(feed)

      result = described_class.new(url).build
      expect(result.native_feed).to eq(feed.to_s)
      expect(Html2rss::Syndication::Discovery).to have_received(:best_feed_url).with(
        hash_including(
          page_url: url,
          request_session: kind_of(Html2rss::RequestSession)
        )
      )
    end

    context 'with a list fixture that shares an item class' do
      subject(:result) do
        response = html_response(File.read('spec/fixtures/local_feed_test.html'))
        articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
        stub_outcome(response, articles:)
        described_class.new(url).build
      end

      it 'emits items+enhance only and channel title', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- fixture contract
        expect(result.articles_count).to eq(3)
        expect(result.has_selectors).to be true
        expect(result.segment_strategy).to eq(:list)
        expect(result.config[:selectors]).to eq(
          items: { selector: 'div.item', enhance: true }
        )
        expect(result.config[:channel]).to include(url:, title: a_string_matching(/\S/), time_zone: 'UTC')
        expect(result.config[:directory]).to include(:topics, :title, :summary)
        expect(result.yaml).to include('# yaml-language-server')
        expect(result.channel_title).to eq(result.config.dig(:channel, :title))
      end
    end

    context 'when HTML is labeled octet-stream' do
      subject(:result) do
        response = html_response(File.read('spec/fixtures/local_feed_test.html'),
                                 content_type: 'application/octet-stream')
        articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
        stub_outcome(response, articles:)
        described_class.new(url).build
      end

      it 'derives selectors from sniffed HTML', :aggregate_failures do
        expect(result.has_selectors).to be true
        expect(result.config[:selectors]).to eq(items: { selector: 'div.item', enhance: true })
      end
    end

    {
      'drops leading html/body/div' => [
        <<~HTML,
          <html><body><div><main><section>
            <article><h2><a href="/a1">Article One Title</a></h2></article>
            <article><h2><a href="/a2">Article Two Title</a></h2></article>
            <article><h2><a href="/a3">Article Three Title</a></h2></article>
          </section></main></div></body></html>
        HTML
        'main > section > article'
      ],
      'keeps mid-path div after trim' => [
        <<~HTML,
          <html><body><main>
            <div>
              <article><h2><a href="/x1">Card One Here Longer</a></h2><p>more text here for item</p></article>
              <article><h2><a href="/x2">Card Two Here Longer</a></h2><p>more text here for item</p></article>
              <article><h2><a href="/x3">Card Three Here Longer</a></h2><p>more text here for item</p></article>
            </div>
          </main></body></html>
        HTML
        'main > div > article'
      ],
      'keeps a single remaining segment' => [
        <<~HTML,
          <html><body>
            <section><h2><a href="/s1">Section One Item</a></h2></section>
            <section><h2><a href="/s2">Section Two Item</a></h2></section>
            <section><h2><a href="/s3">Section Three Item</a></h2></section>
          </body></html>
        HTML
        'section'
      ]
    }.each do |label, (html, expected_items_selector)|
      # rubocop:disable-next RSpec/ExampleLength -- AutoSource + stub + selector assert
      it "trims items path: #{label}" do
        response = html_response(html)
        articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
        stub_outcome(response, articles:)

        expect(described_class.new(url).build.config.dig(:selectors, :items)).to eq(
          selector: expected_items_selector, enhance: true
        )
      end
    end

    it 'lifts heading-link item roots to the research card', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <html><body>
          <article class="research-card">
            <h3><a href="/pub/1">Title of the first publication about research</a></h3>
            <p>Sibling teaser about the first research paper with extra words.</p>
          </article>
          <article class="research-card">
            <h3><a href="/pub/2">Title of the second publication about research</a></h3>
            <p>Sibling teaser about the second research paper with extra words.</p>
          </article>
        </body></html>
      HTML
      response = html_response(html)
      articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
      stub_outcome(response, articles:)

      items = described_class.new(url).build.config.dig(:selectors, :items)
      expect(items[:enhance]).to be true
      expect(items[:selector]).to eq('article.research-card')
    end

    it 'lifts list-strategy heading roots to the enclosing research card', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <html><body>
          <article class="research-card">
            <h3><a href="/pub/1">Title of the first publication about research</a></h3>
            <p>Sibling teaser about the first research paper with extra words.</p>
          </article>
          <article class="research-card">
            <h3><a href="/pub/2">Title of the second publication about research</a></h3>
            <p>Sibling teaser about the second research paper with extra words.</p>
          </article>
        </body></html>
      HTML
      response = html_response(html)
      articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
      stub_outcome(response, articles:)

      allow(Html2rss::AutoSource::Segmenter).to receive(:call) do |sst, strategy:, **|
        next [] unless strategy == :list

        sst.index.each_node.select { |node| node.name.to_s == 'h3' }.map do |heading|
          anchor = heading.children.find { |child| child.name.to_s == 'a' }
          instance_double(Html2rss::AutoSource::Segment, primary_link: anchor, root_node: heading)
        end
      end

      items = described_class.new(url).build.config.dig(:selectors, :items)
      expect(items[:enhance]).to be true
      expect(items[:selector]).to eq('article.research-card')
    end

    it 'keeps Equinor-style wrapping anchors as the item root', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <html><body>
          <a href="/news/one">
            <h2>Equinor starts first offshore wind project</h2>
            <p>The project will add capacity to the North Sea grid this decade.</p>
          </a>
          <a href="/news/two">
            <h2>Equinor starts second offshore wind project</h2>
            <p>The project will add capacity to the North Sea grid this decade.</p>
          </a>
        </body></html>
      HTML
      response = html_response(html)
      articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
      stub_outcome(response, articles:)

      items = described_class.new(url).build.config.dig(:selectors, :items)
      expect(items[:enhance]).to be true
      expect(items[:selector]).to eq('a')
    end

    context 'when selector derivation raises ArgumentError' do
      subject(:result) { described_class.new(url).build }

      let(:articles) do
        [
          Html2rss::Article.new(url: Html2rss::Url.from_absolute("#{url}/1"), title: 'One Two Three', id: '1'),
          Html2rss::Article.new(url: Html2rss::Url.from_absolute("#{url}/2"), title: 'Two Three Four', id: '2')
        ]
      end

      before do
        response = html_response('<html><body></body></html>')
        stub_outcome(response, articles:)
        allow(Html2rss::SST::Normalizer).to receive(:call).and_raise(ArgumentError, 'bad sst')
        allow(Html2rss::Log).to receive(:warn)
      end

      # rubocop:disable-next RSpec/ExampleLength -- default selector plus test next_step
      it 'emits the default items selector when derivation raises ArgumentError', :aggregate_failures do
        expect(result.config[:selectors]).to eq(
          items: { selector: Html2rss::Selectors::DEFAULT_ITEMS_SELECTOR, enhance: true }
        )
        expect(result.has_selectors).to be true
        expect(result.segment_strategy).to eq(:default)
        expect(Html2rss::Log).to have_received(:warn).with(/bad sst/)
        next_step = Html2rss::MCP::Outcome.capture(
          yaml: result.yaml,
          articles_count: result.articles_count,
          has_selectors: result.has_selectors,
          channel_title: result.channel_title,
          requested_strategy: 'auto',
          segment_strategy: result.segment_strategy
        ).next_step
        expect(next_step.name).to eq(:test)
      end
    end

    it 'analyzes a local file when local_file_path is provided', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- local overlay contract
      path = File.expand_path('spec/fixtures/local_feed_test.html')
      result = described_class.build(url, strategy: :local_file, local_file_path: path)

      expect(result.articles_count).to eq(3)
      expect(result.config.dig(:selectors, :items)).to eq(selector: 'div.item', enhance: true)
      expect(result.config[:strategy]).to eq(:local_file)
      expect(result.config.dig(:request, :local_file_path)).to eq(path)
    end

    it 'round-trips local capture config through Html2rss.feed', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- capture→feed contract
      path = File.expand_path('spec/fixtures/local_feed_test.html')
      config = described_class.build(url, strategy: :local_file, local_file_path: path).config

      expect(config[:strategy]).to eq(:local_file)
      expect(config.dig(:request, :local_file_path)).to eq(path)
      expect(config.dig(:selectors, :items, :enhance)).to be true

      feed = Html2rss.feed(config)
      expect(feed).to be_a(RSS::Rss)
      expect(feed.items.size).to be >= 1
    end

    it 'emits hint selector with enhance when items_selector is given', :aggregate_failures do
      stub_outcome(html_response('<html><body></body></html>'), articles: [])

      result = described_class.new(url, items_selector: '.card').build
      expect(result.config[:selectors]).to eq(items: { selector: '.card', enhance: true })
      expect(result.segment_strategy).to eq(:hint)
      expect(result.has_selectors).to be true
    end

    # rubocop:disable-next RSpec/ExampleLength -- empty HTML still gets the default, next_step stays inspect
    it 'emits the default items selector when HTML has no articles', :aggregate_failures do
      stub_outcome(html_response('<html><body></body></html>'), articles: [])

      result = described_class.new(url).build
      expect(result.config[:selectors]).to eq(
        items: { selector: Html2rss::Selectors::DEFAULT_ITEMS_SELECTOR, enhance: true }
      )
      expect(result.segment_strategy).to eq(:default)
      expect(Html2rss::MCP::Outcome.capture(
        yaml: result.yaml,
        articles_count: result.articles_count,
        has_selectors: result.has_selectors,
        channel_title: result.channel_title,
        requested_strategy: 'auto'
      ).next_step.name).to eq(:inspect)
    end

    # rubocop:disable-next RSpec/ExampleLength -- JSON response must not inherit the HTML default
    it 'omits selectors for a non-HTML response', :aggregate_failures do
      response = html_response('[]', content_type: 'application/json')
      article = Html2rss::Article.new(
        url: Html2rss::Url.from_absolute("#{url}/1"), title: 'One Two Three', id: '1'
      )
      stub_outcome(response, articles: [article])

      result = described_class.new(url).build
      expect(result.config[:selectors]).to be_nil
      expect(result.has_selectors).to be false
    end

    it 'stamps selected_strategy into config when AutoFallback chose a concrete strategy' do
      response = html_response(File.read('spec/fixtures/local_feed_test.html'))
      articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
      stub_outcome(response, articles:, selected_strategy: :botasaurus)

      expect(described_class.new(url).build.config[:strategy]).to eq(:botasaurus)
    end

    # rubocop:disable-next RSpec/ExampleLength -- quality-gate miss emits default and test next_step
    it 'emits the default items selector when too few matches', :aggregate_failures do
      html = <<~HTML
        <html><body>
          <article><h2><a href="/only">Only One Article Title</a></h2></article>
        </body></html>
      HTML
      article = Html2rss::Article.new(
        url: Html2rss::Url.from_absolute("#{url}/only"), title: 'Only One Article Title', id: '1'
      )
      stub_outcome(html_response(html), articles: [article])

      result = described_class.new(url).build
      expect(result.has_selectors).to be true
      expect(result.segment_strategy).to eq(:default)
      expect(result.config.dig(:selectors, :items, :selector)).to eq(Html2rss::Selectors::DEFAULT_ITEMS_SELECTOR)
      expect(Html2rss::MCP::Outcome.capture(
        yaml: result.yaml,
        articles_count: result.articles_count,
        has_selectors: result.has_selectors,
        channel_title: result.channel_title,
        requested_strategy: 'auto'
      ).next_step.name).to eq(:test)
    end

    it 'emits unique heading tags for mixed heading runs instead of a parent path', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <html><body>
          <div role="main">
            <h2><a href="/rel/1-0">Release 1.0 notes extra words here</a></h2>
            <p>Details about the first release that make this a real article body.</p>
            <h3><a href="/rel/1-1">Release 1.1 notes extra words here</a></h3>
            <p>Details about the second release that make this a real article body.</p>
            <h2><a href="/rel/2-0">Release 2.0 notes extra words here</a></h2>
            <p>Details about the third release that make this a real article body.</p>
          </div>
        </body></html>
      HTML
      response = html_response(html)
      articles = [
        Html2rss::Article.new(
          url: Html2rss::Url.from_absolute('https://example.com/rel/1-0'),
          title: 'Release 1.0 notes extra words here', id: '1'
        ),
        Html2rss::Article.new(
          url: Html2rss::Url.from_absolute('https://example.com/rel/1-1'),
          title: 'Release 1.1 notes extra words here', id: '2'
        ),
        Html2rss::Article.new(
          url: Html2rss::Url.from_absolute('https://example.com/rel/2-0'),
          title: 'Release 2.0 notes extra words here', id: '3'
        )
      ]
      stub_outcome(response, articles:)

      result = described_class.new(url).build
      expect(result.segment_strategy).to eq(:list)
      expect(result.config.dig(:selectors, :items, :selector)).to eq('h2, h3')
    end

    it 'emits the shared card class when mixed inner permalinks share a parent', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <html><body>
          <div class="card-item">
            <a href="javascript:void(0)">Share</a>
            <h2><a href="/posts/alpha-release">Alpha release notes for the first card</a></h2>
            <p>Description text for the first clustered card goes here extra.</p>
          </div>
          <div class="card-item">
            <a href="mailto:ed@example.com">Email</a>
            <p><a href="/posts/beta-release">Beta release notes for the second card</a></p>
            <p>Description text for the second clustered card goes here extra.</p>
          </div>
          <div class="card-item">
            <a class="card" href="/posts/gamma-release">Gamma release notes for the third card</a>
            <p>Description text for the third clustered card goes here extra.</p>
          </div>
        </body></html>
      HTML
      response = html_response(html)
      articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
      stub_outcome(response, articles:)

      result = described_class.new(url).build
      expect(result.segment_strategy).to eq(:list)
      expect(result.config.dig(:selectors, :items, :selector)).to eq('div.card-item')
    end

    it 'falls back to cluster when list yields too few matches', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      response = html_response('<html><body><div id="root"></div></body></html>')
      articles = [
        Html2rss::Article.new(url: Html2rss::Url.from_absolute("#{url}/a"), title: 'Alpha Beta Gamma', id: '1'),
        Html2rss::Article.new(url: Html2rss::Url.from_absolute("#{url}/b"), title: 'Delta Epsilon Zeta', id: '2')
      ]
      stub_outcome(response, articles:)

      attrs = instance_double(Html2rss::SST::Attrs, class_names: ['card'], href: nil)
      cluster_root = instance_double(Html2rss::SST::Node, name: 'div', tag_path: '/html/body/div.card', attrs:)
      link_a = instance_double(Html2rss::SST::Node, attrs: instance_double(Html2rss::SST::Attrs, href: '/a'))
      link_b = instance_double(Html2rss::SST::Node, attrs: instance_double(Html2rss::SST::Attrs, href: '/b'))
      # rubocop:disable RSpec/VerifiedDoubles -- Segment is a Struct-like collaborator without a stable class API here
      seg_a = double('segment', primary_link: link_a, root_node: cluster_root)
      seg_b = double('segment', primary_link: link_b, root_node: cluster_root)
      # rubocop:enable RSpec/VerifiedDoubles

      allow(Html2rss::AutoSource::Segmenter).to receive(:call) do |_sst, strategy:, **|
        strategy == :list ? [] : [seg_a, seg_b]
      end
      allow(Html2rss::Url).to receive(:from_relative).with('/a', url)
                                                     .and_return(Html2rss::Url.from_absolute("#{url}/a"))
      allow(Html2rss::Url).to receive(:from_relative).with('/b', url)
                                                     .and_return(Html2rss::Url.from_absolute("#{url}/b"))

      result = described_class.new(url).build
      expect(result.segment_strategy).to eq(:cluster)
      expect(result.has_selectors).to be true
      expect(result.config.dig(:selectors, :items, :enhance)).to be true
    end
  end

  context 'when admission drops indicate chrome-heavy listing' do
    it 'defaults enhance to false', :aggregate_failures do
      response = html_response(File.read('spec/fixtures/local_feed_test.html'))
      articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
      stub_outcome(response, articles:, admission_drops: { junk: 2, credit: 1 })

      result = described_class.new(url).build

      expect(result.config.dig(:selectors, :items, :enhance)).to be(false)
    end

    # rubocop:disable-next RSpec/ExampleLength -- chrome drops keep enhance off on the default selector
    it 'keeps enhance off when the default selector covers a chrome-heavy miss', :aggregate_failures do
      html = <<~HTML
        <html><body>
          <article><h2><a href="/only">Only One Article Title</a></h2></article>
        </body></html>
      HTML
      article = Html2rss::Article.new(
        url: Html2rss::Url.from_absolute("#{url}/only"), title: 'Only One Article Title', id: '1'
      )
      stub_outcome(html_response(html), articles: [article], admission_drops: { junk: 2, credit: 1 })

      items = described_class.new(url).build.config.dig(:selectors, :items)
      expect(items[:selector]).to eq(Html2rss::Selectors::DEFAULT_ITEMS_SELECTOR)
      expect(items[:enhance]).to be(false)
    end
  end

  context 'when FeedResolution rewrites the scrape URL' do
    it 'surfaces suggested_channel_url without mutating channel.url', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      response = html_response(
        File.read('spec/fixtures/local_feed_test.html'),
        page_url: 'https://example.com/blog/list'
      )
      articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
      target = Html2rss::ScrapeTarget.new(
        entry_url: url,
        effective_url: 'https://example.com/blog/list'
      )
      stub_outcome(response, articles:, scrape_target: target)

      result = described_class.new(url).build

      expect(result.config.dig(:channel, :url)).to eq(url)
      expect(result.suggested_channel_url).to eq('https://example.com/blog/list')
    end
  end
end
