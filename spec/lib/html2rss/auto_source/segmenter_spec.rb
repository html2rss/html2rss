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
end
