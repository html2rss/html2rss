# frozen_string_literal: true

RSpec.describe Html2rss::Html::SstArticleExtractor do
  def segment_for(html, href: '/news/story') # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    doc = Html2rss::SST::Normalizer.call(html)
    root = doc.root.find { |n| n.name == :article } || doc.root.find { |n| n.name == :div }
    link = root.find { |n| n.link? && n.attrs.href == href } || root.find(&:link?)
    Html2rss::AutoSource::Segment.build(root_node: root, primary_link: link, strategy: :semantic, position: 0)
  end

  describe 'leftover hygiene' do
    let(:extractor_time_zone) { 'UTC' }
    let(:leftover_fields) do
      lambda do |html, item_selector: 'article'|
        wrapped = html.match?(/<html/i) ? html : "<html><body>#{html}</body></html>"
        doc = Html2rss::SST::Normalizer.call(wrapped)
        name = item_selector.to_sym
        root = doc.root.find { |n| n.name == name }
        link = root.find(&:link?)
        segment = Html2rss::AutoSource::Segment.build(
          root_node: root, primary_link: link, strategy: :semantic, position: 0
        )
        article = described_class.call(segment, base_url: 'https://example.com', time_zone: extractor_time_zone)
        { title: article&.title, description: article&.description, published_at: article&.published_at,
          categories: article&.categories || [] }
      end
    end

    it_behaves_like 'article extractor leftover hygiene'
  end

  it 'extracts core article fields from an SST segment', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    html = <<~HTML
      <html><body>
        <article id="story-1" class="category-news" data-category="Launch">
          <h2><a href="/news/story">Story Title</a></h2>
          <time datetime="2026-03-28T12:00:00Z"></time>
          <img src="/hero.jpg" alt="">
          <p>Useful context paragraph with enough words for description extraction.</p>
          <a href="/file.pdf">PDF</a>
        </article>
      </body></html>
    HTML

    article = described_class.call(segment_for(html), base_url: 'https://example.com', scraper: Object)

    expect(article.title).to eq('Story Title')
    expect(article.id).to eq('story-1')
    expect(article.url.to_s).to eq('https://example.com/news/story')
    expect(article.description).to include('Useful context')
    expect(article.image.to_s).to include('hero.jpg')
    expect(article.published_at).to be_a(DateTime)
    expect(article.categories).to include('Launch')
    expect(article.enclosures).not_to be_empty
  end

  it 'accepts RankedSegment and anchorless fallback', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    html = '<html><body><div><strong>Anchorless card text here</strong><p>More words.</p></div></body></html>'
    doc = Html2rss::SST::Normalizer.call(html)
    root = doc.root.find { |n| n.name == :div && n.find { |c| c.name == :strong } }
    segment = Html2rss::AutoSource::Segment.build(root_node: root, primary_link: nil, strategy: :cluster, position: 0)
    ranked = Html2rss::Scoring::RankedSegment.new(
      segment:,
      score: Html2rss::Scoring::Score.new(
        composite: 1.0,
        quality: 1.0,
        junk: 0.0,
        breakdown: Html2rss::Scoring::Score::EMPTY_BREAKDOWN
      )
    )

    article = described_class.call(ranked, base_url: 'https://example.com', fallback_anchorless: true)
    expect(article).to be_a(Html2rss::Article)
    expect(article.title).to eq('Anchorless card text here')
  end

  it 'prefers heading over credit-shaped anchor text', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    html = <<~HTML
      <html><body>
        <article>
          <h2>Real Headline About The Story</h2>
          <a href="/news/story">AFP / Getty Images</a>
          <p>Useful context paragraph with enough words for description extraction.</p>
        </article>
      </body></html>
    HTML

    article = described_class.call(segment_for(html), base_url: 'https://example.com')

    expect(article.title).to eq('Real Headline About The Story')
  end

  it 'returns nil title when the only candidate is credit-shaped', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    html = <<~HTML
      <html><body>
        <article>
          <a href="/news/story">Photo: Reuters</a>
          <p>Useful context paragraph with enough words for description extraction.</p>
        </article>
      </body></html>
    HTML

    article = described_class.call(segment_for(html), base_url: 'https://example.com')

    expect(article).to be_a(Html2rss::Article)
    expect(article.title).to be_nil
  end

  it 'keeps slug-shaped titles present so Cleanup can reject them', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    html = <<~HTML
      <html><body>
        <article>
          <a href="/news/story">story-has-edit-branch</a>
          <p>Useful context paragraph with enough words for description extraction.</p>
        </article>
      </body></html>
    HTML

    article = described_class.call(segment_for(html), base_url: 'https://example.com')

    expect(article.title).to eq('story-has-edit-branch')
    expect(Html2rss::AutoSource::Cleanup.junk_reason(article.title)).to eq(:slug)
  end

  it 'prefers real anchor text when the heading is credit-shaped', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    html = <<~HTML
      <html><body>
        <article>
          <h2>AFP / Getty Images</h2>
          <a href="/news/story">Real Headline About The Story</a>
          <p>Useful context paragraph with enough words for description extraction.</p>
        </article>
      </body></html>
    HTML

    article = described_class.call(segment_for(html), base_url: 'https://example.com')

    expect(article.title).to eq('Real Headline About The Story')
  end

  it 'extracts a background-image style URL as the article image', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    html = <<~HTML
      <html><body>
        <article>
          <h2><a href="/news/style">Style Image Story</a></h2>
          <div style="background-image: url('/assets/hero-banner.jpg')"></div>
          <p>Useful context paragraph with enough words for description extraction.</p>
        </article>
      </body></html>
    HTML

    article = described_class.call(segment_for(html, href: '/news/style'), base_url: 'https://example.com')

    expect(article.image.to_s).to include('hero-banner.jpg')
  end

  it 'extracts zip archive enclosures from normalized HTML', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    html = <<~HTML
      <html><body>
        <article>
          <h2><a href="/news/media">Media Enclosures Story</a></h2>
          <p>Useful context paragraph with enough words for description extraction.</p>
          <a href="/downloads/bundle.zip">Download ZIP</a>
        </article>
      </body></html>
    HTML

    article = described_class.call(segment_for(html, href: '/news/media'), base_url: 'https://example.com')
    zip = article.enclosures.find { |enclosure| enclosure.type == 'application/zip' }

    expect(zip).not_to be_nil
    expect(zip.url.to_s).to eq('https://example.com/downloads/bundle.zip')
  end

  it 'extracts iframe enclosures when present on an SST segment', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    link = Html2rss::SST::Node.build(
      name: :a,
      attrs: Html2rss::SST::Attrs.build(href: '/news/embed'),
      own_text: 'Embed Story'
    )
    iframe = Html2rss::SST::Node.build(
      name: :iframe,
      attrs: Html2rss::SST::Attrs.build(src: '/embeds/player.html')
    )
    root = Html2rss::SST::Node.build(
      name: :article,
      children: [
        Html2rss::SST::Node.build(name: :h2, children: [link]),
        Html2rss::SST::Node.build(name: :p, own_text: 'Useful context paragraph with enough words.'),
        iframe
      ]
    )
    segment = Html2rss::AutoSource::Segment.build(
      root_node: root, primary_link: link, strategy: :semantic, position: 0
    )

    article = described_class.call(segment, base_url: 'https://example.com')
    frame = article.enclosures.find { |enclosure| enclosure.type == 'text/html' }

    expect(frame).not_to be_nil
    expect(frame.url.to_s).to eq('https://example.com/embeds/player.html')
  end
end
