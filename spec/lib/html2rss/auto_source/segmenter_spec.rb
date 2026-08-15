# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Segmenter do
  def document_for(html)
    Html2rss::SST::Normalizer.call(html)
  end

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

    it 'clusters repeated tag_path anchors into article segments', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
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
        minimum_selector_frequency: 3
      )

      expect(segments.size).to eq(3)
      expect(segments.first.root_node.attrs.class_names).to include('card-item')
      expect(segments.map(&:strategy).uniq).to eq([:cluster])
    end
  end
end
