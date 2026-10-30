# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Segmenter do
  describe '.call with :semantic' do
    let(:html) do
      <<~HTML
        <html><body>
          <nav><a href="/home">Home</a></nav>
          <article>
            <h2><a href="/posts/one">Post One</a></h2>
            <p>Detailed summary for the first post goes here.</p>
          </article>
          <article>
            <h2><a href="/posts/two">Post Two</a></h2>
            <p>Detailed summary for the second post goes here.</p>
          </article>
        </body></html>
      HTML
    end

    it 'returns typed Segments with primary links, skipping nav chrome', :aggregate_failures do
      segments = described_class.call(document_for(html), base_url: 'https://example.com', strategy: :semantic)

      expect(segments).to all(be_a(Html2rss::AutoSource::Segment))
      expect(segments.map { _1.primary_link.attrs.href }).to eq(%w[/posts/one /posts/two])
      expect(segments.map(&:strategy).uniq).to eq([:semantic])
    end
  end

  describe '.call with :list' do
    let(:html) do
      <<~HTML
        <html><body>
          <nav>
            <a href="/home">Home</a>
            <a href="/about">About</a>
            <a href="/contact">Contact</a>
          </nav>
          <main>
            <article><a href="/posts/1">Post 1</a></article>
            <article><a href="/posts/2">Post 2</a></article>
            <article><a href="/posts/3">Post 3</a></article>
          </main>
        </body></html>
      HTML
    end

    it 'groups repeated list cards under a shared parent', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      segments = described_class.call(
        document_for(html),
        base_url: 'https://example.com',
        strategy: :list,
        minimum_selector_frequency: 3,
        use_top_selectors: 3
      )

      expect(segments.size).to eq(3)
      expect(segments.map { _1.primary_link.attrs.href }).to eq(%w[/posts/1 /posts/2 /posts/3])
    end

    it 'groups mixed heading and card anchors by parent and keeps only main', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <html><body>
          <section>
            <h2><a href="/outside/one">Outside One Title Extra Words</a></h2>
            <a class="card" href="/outside/two">Outside Two Title Extra Words</a>
            <h2><a href="/outside/three">Outside Three Title Extra Words</a></h2>
            <a class="card" href="/outside/four">Outside Four Title Extra Words</a>
          </section>
          <main>
            <div>
              <h2><a href="/posts/one">Post One Title Extra Words</a></h2>
              <a class="card" href="/posts/two">Post Two Title Extra Words</a>
              <h2><a href="/posts/three">Post Three Title Extra Words</a></h2>
              <a class="card" href="/posts/four">Post Four Title Extra Words</a>
            </div>
          </main>
        </body></html>
      HTML

      segments = described_class.call(document_for(html), base_url: 'https://example.com', strategy: :list)

      expect(segments.map { _1.primary_link.attrs.href }).to eq(
        %w[/posts/one /posts/two /posts/three /posts/four]
      )
    end

    it 'groups mixed heading levels under one parent, including role=main', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <html><body>
          <section>
            <h2><a href="/outside/one">Outside One Title Extra Words</a></h2>
            <h3><a href="/outside/two">Outside Two Title Extra Words</a></h3>
          </section>
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

      segments = described_class.call(document_for(html), base_url: 'https://example.com', strategy: :list)

      expect(segments.map { _1.primary_link.attrs.href }).to eq(%w[/rel/1-0 /rel/1-1 /rel/2-0])
      expect(segments.map { _1.root_node.name }).to eq(%i[h2 h3 h2])
    end

    it 'keeps same-shaped links eligible when the document has no main', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <html><body>
          <section>
            <h2><a href="/outside/one">Outside One Title Extra Words</a></h2>
            <a class="card" href="/outside/two">Outside Two Title Extra Words</a>
            <h2><a href="/outside/three">Outside Three Title Extra Words</a></h2>
            <a class="card" href="/outside/four">Outside Four Title Extra Words</a>
          </section>
          <div>
            <h2><a href="/posts/one">Post One Title Extra Words</a></h2>
            <a class="card" href="/posts/two">Post Two Title Extra Words</a>
            <h2><a href="/posts/three">Post Three Title Extra Words</a></h2>
            <a class="card" href="/posts/four">Post Four Title Extra Words</a>
          </div>
        </body></html>
      HTML

      segments = described_class.call(document_for(html), base_url: 'https://example.com', strategy: :list)
      hrefs = segments.map { _1.primary_link.attrs.href }

      expect(hrefs).to include('/outside/one', '/posts/one')
    end
  end

  describe '#landmark_ancestor?' do
    it 'is true for anchors under utility landmarks outside the content container', # rubocop:disable RSpec/ExampleLength
       :aggregate_failures do
      document = document_for(<<~HTML)
        <html><body>
          <article>
            <nav><a href="/news/2024/platform-launch-notes">Related</a></nav>
            <h2><a href="/news/2024/other-story">Other story</a></h2>
          </article>
        </body></html>
      HTML
      container = document.root.find { |n| n.name == :article }
      landmark_anchor = container.find { |n| n.link? && n.visible_text.to_s == 'Related' }
      content_anchor = container.find { |n| n.link? && n.visible_text.to_s == 'Other story' }
      segmenter = described_class.new(document, base_url: 'https://example.com', strategy: :semantic)

      expect(segmenter.landmark_ancestor?(landmark_anchor, container)).to be(true)
      expect(segmenter.landmark_ancestor?(content_anchor, container)).to be(false)
    end
  end

  describe Html2rss::AutoSource::Segmenter::Semantic do
    let(:hrefs) { segments.map { _1.primary_link.attrs.href } }
    let(:options) { {} }
    let(:segments) do
      Html2rss::AutoSource::Segmenter.call(document_for(html), base_url: 'https://example.com', strategy: :semantic,
                                                               **options)
    end

    context 'when a container wraps another article' do
      let(:html) do
        <<~HTML
          <html><body>
            <article>
              <p>Outer wrapper text that is not the story itself.</p>
              <article><a href="/news/2024/inner-story">Inner story title</a></article>
            </article>
          </body></html>
        HTML
      end

      it 'keeps only the leaf container' do
        expect(hrefs).to eq(%w[/news/2024/inner-story])
      end
    end

    context 'when a deeper container appears after a shallow one' do
      let(:html) do
        <<~HTML
          <html><body>
            <article><a href="/news/2024/shallow-story">Shallow story title</a></article>
            <section><div><article><a href="/news/2024/deep-story">Deep story title</a></article></div></section>
          </body></html>
        HTML
      end

      it 'orders the deeper container first' do
        expect(hrefs).to eq(%w[/news/2024/deep-story /news/2024/shallow-story])
      end
    end

    context 'when a list item wraps an article' do
      let(:html) do
        <<~HTML
          <html><body>
            <ul><li><article><a href="/news/2024/listed-story">Listed story title</a></article></li></ul>
          </body></html>
        HTML
      end

      it 'rejects the wrapping list item' do
        expect(hrefs).to eq(%w[/news/2024/listed-story])
      end
    end

    context 'when a candidate sits inside page chrome' do
      let(:html) do
        <<~HTML
          <html><body>
            <footer><article><a href="/news/2024/footer-story">Footer story title</a></article></footer>
            <article><a href="/news/2024/main-story">Main story title</a></article>
          </body></html>
        HTML
      end

      it 'skips the chrome candidate' do
        expect(hrefs).to eq(%w[/news/2024/main-story])
      end
    end

    context 'when a container has no link' do
      let(:html) do
        <<~HTML
          <html><body><article><p>Plain paragraph without any link at all here.</p></article></body></html>
        HTML
      end

      it 'drops the container by default' do
        expect(segments).to be_empty
      end

      it 'keeps the unanchored container when permitted' do
        options[:permit_unanchored] = true
        expect(segments.map(&:primary_link)).to eq([nil])
      end
    end
  end

  describe Html2rss::AutoSource::Segmenter::PrimaryLink do
    let(:document) { document_for(html) }
    let(:segmenter) { Html2rss::AutoSource::Segmenter.new(document, base_url: 'https://example.com', strategy: :semantic) }
    let(:container) { document.root.find { |node| node.name == :article } }
    let(:picked) { described_class.new(segmenter).select(container) }

    context 'when a heading anchor competes with a plain text link' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <a href="/news/2024/read-more-story">Read the full story</a>
            <h2><a href="/news/2024/headline-story">Headline story title</a></h2>
          </article></body></html>
        HTML
      end

      it 'selects the heading anchor' do
        expect(picked.attrs.href).to eq('/news/2024/headline-story')
      end
    end

    context 'when two anchors share one destination with equal scores' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <p><a href="/news/2024/shared-story">First shared label</a></p>
            <p><a href="/news/2024/shared-story">Second shared label</a></p>
          </article></body></html>
        HTML
      end

      it 'keeps the first anchor in document order' do
        expect(picked).to be(container.find(&:link?))
      end
    end

    context 'when a higher-scoring anchor sits inside page chrome' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <nav><h2><a href="/news/2024/nav-headline">Nav headline text</a></h2></nav>
            <p><a href="/news/2024/body-story">Body story text</a></p>
          </article></body></html>
        HTML
      end

      it 'ignores the chrome anchor and selects the body link' do
        expect(picked.attrs.href).to eq('/news/2024/body-story')
      end
    end

    context 'when an anchor has no text and a non-content destination' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <a href="/x/y"><img src="/a.png" alt=""></a>
          </article></body></html>
        HTML
      end

      it 'returns nil' do
        expect(picked).to be_nil
      end
    end
  end

  describe Html2rss::AutoSource::Segmenter::PrimaryLink, 'scoring and ordering' do
    let(:document) { document_for(html) }
    let(:segmenter) { Html2rss::AutoSource::Segmenter.new(document, base_url: 'https://example.com', strategy: :semantic) }
    let(:container) { document.root.find { |node| node.name == :article } }
    let(:picked) { described_class.new(segmenter).select(container) }

    context 'when a higher-scoring anchor comes first and a lower-scoring one last' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <h2><a href="/news/2024/headline">Headline text</a></h2>
            <p><a href="/news/2024/body">Body text here</a></p>
          </article></body></html>
        HTML
      end

      it 'selects the highest-scoring anchor regardless of order' do
        expect(picked.attrs.href).to eq('/news/2024/headline')
      end
    end

    context 'when an unscoreable anchor precedes a valid one' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <a href="javascript:void(0)"></a>
            <p><a href="/news/2024/body">Body text here</a></p>
          </article></body></html>
        HTML
      end

      it 'skips the unscoreable anchor and selects the valid one' do
        expect(picked.attrs.href).to eq('/news/2024/body')
      end
    end

    context 'when a heading anchor and a plain anchor share a destination' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <p><a href="/news/2024/shared">Plain label</a></p>
            <h2><a href="/news/2024/shared">Headline label</a></h2>
          </article></body></html>
        HTML
      end

      it 'keeps the heading anchor as the destination winner', :aggregate_failures do
        expect(picked.visible_text.to_s.strip).to eq('Headline label')
        expect(picked.attrs.href).to eq('/news/2024/shared')
      end
    end

    context 'when a heading anchor precedes a lower-scoring anchor to the same destination' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <h2><a href="/news/2024/shared">Headline label</a></h2>
            <p><a href="/news/2024/shared">Plain label</a></p>
          </article></body></html>
        HTML
      end

      it 'keeps the heading anchor' do
        expect(picked.visible_text.to_s.strip).to eq('Headline label')
      end
    end

    context 'when a heading anchor sits in a heading whose text differs from the anchor' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <a href="/news/2024/read-more">Read the full story</a>
            <h2>Lead: <a href="/news/2024/headline">Headline</a></h2>
          </article></body></html>
        HTML
      end

      it 'selects the heading anchor by its heading position' do
        expect(picked.attrs.href).to eq('/news/2024/headline')
      end
    end

    context 'when an anchor with a missing destination sits in a heading' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <h2><a href="javascript:void(0)">Headline text</a></h2>
            <p><a href="/news/2024/body">Body text here</a></p>
          </article></body></html>
        HTML
      end

      it 'ignores the unresolved destination' do
        expect(picked.attrs.href).to eq('/news/2024/body')
      end
    end

    context 'when an empty heading anchor has a non-content destination' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <h2><a href="/x/y"></a></h2>
          </article></body></html>
        HTML
      end

      it 'keeps the heading anchor' do
        expect(picked.attrs.href).to eq('/x/y')
      end
    end

    context 'when a plain anchor matches the heading text exactly after trimming' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <h2>
              Title
            </h2>
            <p><a href="/news/2024/other">Other words</a></p>
            <p><a href="/news/2024/title-link">
              Title
            </a></p>
          </article></body></html>
        HTML
      end

      it 'prefers the anchor whose text matches the heading' do
        expect(picked.attrs.href).to eq('/news/2024/title-link')
      end
    end

    context 'when an icon-only content anchor precedes a text anchor' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <p><a href="/news/2024/icon-only"><img src="/a.png" alt=""></a></p>
            <p><a href="/x/y">Plain words</a></p>
          </article></body></html>
        HTML
      end

      it 'rejects the icon-only anchor as noise' do
        expect(picked.attrs.href).to eq('/x/y')
      end
    end

    context 'when a navigation landmark anchor precedes a body anchor' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <nav><a href="/news/2024/nav-story">Nav story words</a></nav>
            <p><a href="/x/y">Body words</a></p>
          </article></body></html>
        HTML
      end

      it 'rejects the landmark anchor as noise' do
        expect(picked.attrs.href).to eq('/x/y')
      end
    end

    context 'when a content-like destination competes with a non-content one' do
      let(:html) do
        <<~HTML
          <html><body><article>
            <p><a href="/x/y">Plain words</a></p>
            <p><a href="/news/2024/story">Story words</a></p>
          </article></body></html>
        HTML
      end

      it 'prefers the content-like destination' do
        expect(picked.attrs.href).to eq('/news/2024/story')
      end
    end
  end

  describe '.call with :cluster' do
    let(:html) do
      <<~HTML
        <html><body>
          <nav class="nav"><a class="nav-link" href="/home">Home</a></nav>
          <main>
            <div class="card-item p-4">
              <span class="card-title font-bold">Release v1.0</span>
              <p class="card-body">Description text for release one goes here.</p>
            </div>
            <div class="card-item p-4">
              <span class="card-title font-bold">Release v2.0</span>
              <p class="card-body">Description text for release two goes here.</p>
            </div>
            <div class="card-item p-4">
              <span class="card-title font-bold">Release v3.0</span>
              <p class="card-body">Description text for release three goes here.</p>
            </div>
          </main>
        </body></html>
      HTML
    end

    it 'returns the highest scoring class group as cluster segments', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      segments = described_class.call(
        document_for(html),
        base_url: 'https://example.com',
        strategy: :cluster,
        minimum_selector_frequency: 3,
        permit_unanchored: true
      )

      expect(segments.size).to eq(3)
      expect(segments.first.root_node.attrs.class_names).to include('card-item')
      expect(segments.map(&:strategy).uniq).to eq([:cluster])
      expect(segments.map(&:primary_link)).to all(be_nil)
    end

    it 'groups mixed-case class tokens into one cluster', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <html><body>
          <div class="PostCard p-4">
            <span class="card-title font-bold">Release v1.0</span>
            <p class="card-body">Description text for release one goes here.</p>
          </div>
          <div class="postcard p-4">
            <span class="card-title font-bold">Release v2.0</span>
            <p class="card-body">Description text for release two goes here.</p>
          </div>
          <div class="PostCard p-4">
            <span class="card-title font-bold">Release v3.0</span>
            <p class="card-body">Description text for release three goes here.</p>
          </div>
        </body></html>
      HTML

      segments = described_class.call(
        document_for(html),
        base_url: 'https://example.com',
        strategy: :cluster,
        minimum_selector_frequency: 3,
        permit_unanchored: true
      )

      expect(segments.size).to eq(3)
      expect(segments.first.root_node.attrs.class_names).to include('PostCard').or include('postcard')
      expect(segments.map(&:strategy).uniq).to eq([:cluster])
      expect(segments.map(&:primary_link)).to all(be_nil)
    end

    it 'keeps the content href on anchored cards, not javascript: or mailto:', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <html><body>
          <div class="card-item p-4">
            <a href="javascript:void(0)">Share</a>
            <h2><a href="/posts/alpha-release">Alpha release notes for the first card</a></h2>
            <p>Description text for the first clustered card goes here extra.</p>
          </div>
          <div class="card-item p-4">
            <a href="mailto:ed@example.com">Email</a>
            <h2><a href="/posts/beta-release">Beta release notes for the second card</a></h2>
            <p>Description text for the second clustered card goes here extra.</p>
          </div>
          <div class="card-item p-4">
            <a href="javascript:void(0)">Share</a>
            <h2><a href="/posts/gamma-release">Gamma release notes for the third card</a></h2>
            <p>Description text for the third clustered card goes here extra.</p>
          </div>
        </body></html>
      HTML

      segments = described_class.call(
        document_for(html),
        base_url: 'https://example.com',
        strategy: :cluster,
        minimum_selector_frequency: 3,
        permit_unanchored: false
      )

      expect(segments.size).to eq(3)
      expect(segments.map { _1.primary_link.attrs.href }).to eq(
        %w[/posts/alpha-release /posts/beta-release /posts/gamma-release]
      )
    end

    it 'attaches content hrefs when list cannot group isolated class cards', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <html><body>
          <section>
            <nav><a href="/news/alpha-sidebar-notes">Alpha sidebar notes extra words here</a></nav>
            <div class="card-item">
              <a href="javascript:void(0)">Share</a>
              <h2><a href="/posts/alpha-release">Alpha release notes for the first card</a></h2>
              <p>Description text for the first clustered card goes here extra.</p>
            </div>
          </section>
          <section>
            <nav><a href="/news/beta-sidebar-notes">Beta sidebar notes extra words here</a></nav>
            <div class="card-item">
              <a href="mailto:ed@example.com">Email</a>
              <h2><a href="/posts/beta-release">Beta release notes for the second card</a></h2>
              <p>Description text for the second clustered card goes here extra.</p>
            </div>
          </section>
          <section>
            <nav><a href="/news/gamma-sidebar-notes">Gamma sidebar notes extra words here</a></nav>
            <div class="card-item">
              <a href="javascript:void(0)">Share</a>
              <h2><a href="/posts/gamma-release">Gamma release notes for the third card</a></h2>
              <p>Description text for the third clustered card goes here extra.</p>
            </div>
          </section>
        </body></html>
      HTML
      document = document_for(html)

      list = described_class.call(document, base_url: 'https://example.com', strategy: :list)
      cluster = described_class.call(
        document, base_url: 'https://example.com', strategy: :cluster, permit_unanchored: false
      )

      expect(list).to be_empty
      expect(cluster.map { _1.primary_link.attrs.href }).to eq(
        %w[/posts/alpha-release /posts/beta-release /posts/gamma-release]
      )
    end
  end

  describe '.call with :cluster grouping' do
    let(:entry) do
      lambda do |slug, label|
        <<~HTML
          <div class="entry"><h2><a href="/posts/#{slug}">#{label} release notes for the entry</a></h2>
          <p>Description text for the #{slug} entry goes here.</p></div>
        HTML
      end
    end

    let(:cluster_segments) do
      lambda do |html, **opts|
        described_class.call(document_for(html), base_url: 'https://example.com', strategy: :cluster, **opts)
      end
    end

    context 'when layout wrappers hold several cluster cards' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="row">#{entry.call('alpha', 'Alpha')}#{entry.call('beta', 'Beta')}</div>
            <div class="row">#{entry.call('gamma', 'Gamma')}#{entry.call('delta', 'Delta')}</div>
          </main></body></html>
        HTML
      end

      it 'drops the wrappers and keeps the cards', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: false)

        expect(segments.map { _1.root_node.attrs.class_names }).to all(include('entry'))
        expect(segments.map { _1.primary_link.attrs.href })
          .to eq(%w[/posts/alpha /posts/beta /posts/gamma /posts/delta])
      end
    end

    context 'when a layout wrapper holds exactly one card body' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="card-wrap"><div class="card-body"><h2><a href="/posts/alpha">Alpha release notes for the first card</a></h2><p>Description text for alpha card goes here.</p></div></div>
            <div class="card-wrap"><div class="card-body"><h2><a href="/posts/beta">Beta release notes for the second card</a></h2><p>Description text for beta card goes here.</p></div></div>
            <div class="card-wrap"><div class="card-body"><h2><a href="/posts/gamma">Gamma release notes for the third card</a></h2><p>Description text for gamma card goes here.</p></div></div>
          </main></body></html>
        HTML
      end

      it 'keeps the nested card body as the cluster root', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: false)

        expect(segments.size).to eq(3)
        expect(segments.map { _1.root_node.attrs.class_names }).to all(include('card-body'))
      end
    end

    context 'when a layout wrapper holds a single non-layout inner node' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="card-wrap"><span class="card-body"><a href="/posts/alpha">Alpha release notes for the first card</a> extra words here</span></div>
            <div class="card-wrap"><span class="card-body"><a href="/posts/beta">Beta release notes for the second card</a> extra words here</span></div>
            <div class="card-wrap"><span class="card-body"><a href="/posts/gamma">Gamma release notes for the third card</a> extra words here</span></div>
          </main></body></html>
        HTML
      end

      it 'keeps the outer wrapper as the cluster root', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: true)

        expect(segments.size).to eq(3)
        expect(segments.map { _1.root_node.attrs.class_names }).to all(include('card-wrap'))
      end
    end

    context 'when blocks are unclassed but share a structure' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div><h2><a href="/posts/alpha">Alpha release notes for the first entry</a></h2><p>Description text for alpha goes here.</p></div>
            <div><h2><a href="/posts/beta">Beta release notes for the second entry</a></h2><p>Description text for beta goes here.</p></div>
            <div><h2><a href="/posts/gamma">Gamma release notes for the third entry</a></h2><p>Description text for gamma goes here.</p></div>
          </main></body></html>
        HTML
      end

      it 'emits one segment per block and honours the frequency floor', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: false)

        expect(segments.map { _1.root_node.name }).to eq(%i[div div div])
        expect(cluster_segments.call(html, permit_unanchored: false, minimum_selector_frequency: 4)).to be_empty
      end
    end

    context 'when class tokens repeat in a different order' do
      let(:html) do
        <<~HTML
          <html><body>
            <div class="card b-x"><p>Description text for the first card goes here extra.</p></div>
            <div class="b-x card"><p>Description text for the second card goes here extra.</p></div>
            <div class="card b-x"><p>Description text for the third card goes here extra.</p></div>
          </body></html>
        HTML
      end

      it 'groups them into one cluster', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: true, minimum_selector_frequency: 3)

        expect(segments.size).to eq(3)
      end
    end

    context 'when classed cards and unclassed blocks both repeat' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="card"><h2><a href="/posts/alpha">Alpha release notes for the first card</a></h2><p>Description text for alpha card goes here.</p></div>
            <div class="card"><h2><a href="/posts/beta">Beta release notes for the second card</a></h2><p>Description text for beta card goes here.</p></div>
            <div class="card"><h2><a href="/posts/gamma">Gamma release notes for the third card</a></h2><p>Description text for gamma card goes here.</p></div>
            <section><p>Unclassed structure block one with words.</p></section>
            <section><p>Unclassed structure block two with words.</p></section>
          </main></body></html>
        HTML
      end

      it 'selects the classed card group', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: false)

        expect(segments.map { _1.root_node.attrs.class_names }).to all(include('card'))
        expect(segments.size).to eq(3)
      end
    end

    context 'when no group repeats' do
      let(:html) do
        '<html><body><main><div><p>Only one unique block of descriptive text here.</p></div></main></body></html>'
      end

      it 'returns no cluster segments' do
        expect(cluster_segments.call(html, permit_unanchored: true)).to be_empty
      end
    end

    context 'when a class group sits exactly at the frequency floor' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="tile"><a href="/posts/alpha">Alpha tile headline for the first post</a></div>
            <div class="tile"><a href="/posts/beta">Beta tile headline for the second post</a></div>
          </main></body></html>
        HTML
      end

      it 'keeps the group at the floor and drops it below a higher floor', :aggregate_failures do
        expect(cluster_segments.call(html, permit_unanchored: false).map { _1.primary_link.attrs.href })
          .to eq(%w[/posts/alpha /posts/beta])
        expect(cluster_segments.call(html, permit_unanchored: false, minimum_selector_frequency: 3)).to be_empty
      end
    end

    context 'when classed blocks repeat with different child structures' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="tile"><a href="/posts/alpha">Alpha tile headline for the first post</a><p>Alpha summary text.</p></div>
            <div class="tile"><p>Beta summary text first in the tile.</p><a href="/posts/beta">Beta tile headline for the second post</a></div>
            <div class="tile"><span>Gamma detail words</span><a href="/posts/gamma">Gamma tile headline for the third post</a></div>
          </main></body></html>
        HTML
      end

      it 'groups the blocks by class token rather than child structure', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: false)

        expect(segments.map { _1.primary_link.attrs.href }).to eq(%w[/posts/alpha /posts/beta /posts/gamma])
        expect(segments.map { _1.root_node.attrs.class_names }).to all(include('tile'))
      end
    end

    context 'when excluded chrome repeats the same class as content cards' do
      let(:html) do
        <<~HTML
          <html><body>
            <nav class="tile"><a href="/home">Home page link</a></nav>
            <nav class="tile"><a href="/about">About page link</a></nav>
            <nav class="tile"><a href="/contact">Contact page link</a></nav>
            <main>
              <div class="tile"><a href="/posts/alpha">Alpha tile headline for the first post</a></div>
              <div class="tile"><a href="/posts/beta">Beta tile headline for the second post</a></div>
            </main>
          </body></html>
        HTML
      end

      it 'keeps only the content cards in the cluster', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: false)

        expect(segments.map { _1.primary_link.attrs.href }).to eq(%w[/posts/alpha /posts/beta])
        expect(segments.map { _1.root_node.name }).to all(eq(:div))
      end
    end

    context 'when a wrapper holds only one card of a layout group' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="row"><div class="cell"><a href="/posts/alpha">Alpha cell headline words</a></div> Extra row commentary words that make the wrapper heavier than its cell.</div>
            <div class="row"><div class="cell"><a href="/posts/beta">Beta cell headline words</a></div> Extra row commentary words that make the wrapper heavier than its cell.</div>
          </main></body></html>
        HTML
      end

      it 'does not treat the single-card wrapper as a container', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: false)

        expect(segments.size).to eq(2)
        expect(segments.map { _1.root_node.attrs.class_names }).to all(include('row'))
      end
    end

    context 'when one wrapper holds two cards and another holds one' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <section class="block"><div class="card"><a href="/posts/alpha">Alpha card headline words for the first story in this block set</a></div><div class="card"><a href="/posts/beta">Beta card headline words for the second story in this block set</a></div> #{'Section commentary words here. ' * 5}</section>
            <section class="block"><div class="card"><a href="/posts/gamma">Gamma card headline words for the third story in this block set</a></div> #{'Section commentary words here. ' * 5}</section>
          </main></body></html>
        HTML
      end

      it 'drops the wrapper that contains several cards', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: false)

        expect(segments.map { _1.root_node.attrs.class_names }).to all(include('card'))
        expect(segments.map { _1.primary_link.attrs.href }).to eq(%w[/posts/alpha /posts/beta /posts/gamma])
      end
    end

    context 'when a wrapper holds several non-layout chips' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="wrap"><span class="chip">Alpha chip label with eight words here</span><span class="chip">Beta chip label with eight words here</span> #{'Wrapper commentary words here. ' * 4}</div>
            <div class="wrap"><span class="chip">Gamma chip label with eight words here</span><span class="chip">Delta chip label with eight words here</span> #{'Wrapper commentary words here. ' * 4}</div>
          </main></body></html>
        HTML
      end

      it 'keeps the wrapper because chips are not layout containers', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: true)

        expect(segments.map { _1.root_node.attrs.class_names }).to all(include('wrap'))
        expect(segments.size).to eq(2)
      end
    end

    context 'when only some members of a group nest inside their partner group' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="frame"><div class="inner">Alpha inner words for the first frame story here</div></div>
            <div class="frame"><div class="inner">Beta inner words for the second frame story here</div></div>
            <div class="frame">Gamma frame words without any inner wrapper here</div>
            <div class="inner">Gamma inner words stranded outside the frame</div>
          </main></body></html>
        HTML
      end

      it 'keeps both groups when the pairing is not fully nested', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: true)

        expect(segments.map { _1.root_node.attrs.class_names }).to all(include('frame'))
        expect(segments.size).to eq(3)
      end
    end

    context 'when more class groups repeat than the overlap resolver caps' do
      let(:filler_groups) do
        Array.new(40) do |index|
          %(<div class="s#{index}"><a href="/x/#{index}">Filler #{index} headline words for this group</a></div>) * 3
        end.join
      end
      let(:html) do
        <<~HTML
          <html><body><main>#{filler_groups}
            <div class="special"><a href="/posts/alpha">Alpha special headline for the pair</a><p>#{'Rich descriptive words repeat here. ' * 6}</p></div>
            <div class="special"><a href="/posts/beta">Beta special headline for the pair</a><p>#{'Rich descriptive words repeat here. ' * 6}</p></div>
          </main></body></html>
        HTML
      end

      it 'drops the smallest group when more than forty groups repeat', :aggregate_failures do
        segments = cluster_segments.call(html, permit_unanchored: false)

        expect(segments.map { _1.root_node.attrs.class_names }.flatten).not_to include('special')
        expect(segments.size).to eq(3)
      end
    end
  end
end
