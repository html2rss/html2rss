# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Capture do
  let(:url) { 'https://example.com/blog' }

  def html_response(body, page_url: url)
    Html2rss::RequestService::Response.new(
      body:,
      url: Html2rss::Url.from_absolute(page_url),
      headers: { 'content-type' => 'text/html' }
    )
  end

  def stub_outcome(response, articles:, admission_drops: {}, selected_strategy: nil)
    outcome = instance_double(
      Html2rss::FeedPipeline::PipelineOutcome,
      response:,
      articles:,
      admission_drops:,
      selected_strategy:
    )
    allow(Html2rss::FeedPipeline).to receive(:new)
      .and_return(instance_double(Html2rss::FeedPipeline, to_outcome: outcome))
    outcome
  end

  describe '#build' do
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
        expect(result.channel_title).to eq(result.config.dig(:channel, :title))
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
      # rubocop:disable RSpec/ExampleLength -- AutoSource + stub + selector assert
      it "trims items path: #{label}" do
        response = html_response(html)
        articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
        stub_outcome(response, articles:)

        expect(described_class.new(url).build.config.dig(:selectors, :items)).to eq(
          selector: expected_items_selector, enhance: true
        )
      end
      # rubocop:enable RSpec/ExampleLength
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

      it 'warns and omits selectors', :aggregate_failures do
        expect(result.config[:selectors]).to be_nil
        expect(result.has_selectors).to be false
        expect(Html2rss::Log).to have_received(:warn).with(/bad sst/)
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

    it 'stamps selected_strategy into config when AutoFallback chose a concrete strategy' do
      response = html_response(File.read('spec/fixtures/local_feed_test.html'))
      articles = Html2rss::AutoSource.new(response, Html2rss::AutoSource::DEFAULT_CONFIG).articles
      stub_outcome(response, articles:, selected_strategy: :botasaurus)

      expect(described_class.new(url).build.config[:strategy]).to eq(:botasaurus)
    end

    # rubocop:disable RSpec/ExampleLength -- single-article quality gate
    it 'reports has_selectors false when too few matches' do
      html = <<~HTML
        <html><body>
          <article><h2><a href="/only">Only One Article Title</a></h2></article>
        </body></html>
      HTML
      article = Html2rss::Article.new(
        url: Html2rss::Url.from_absolute("#{url}/only"), title: 'Only One Article Title', id: '1'
      )
      stub_outcome(html_response(html), articles: [article])

      expect(described_class.new(url).build.has_selectors).to be false
    end
    # rubocop:enable RSpec/ExampleLength

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
end
