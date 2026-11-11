# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::PageLinks do
  subject(:page_links) { described_class.build(document, link_resolver:) }

  let(:link_resolver) { Html2rss::Scoring::LinkResolver.new('https://example.com/news/') }
  let(:document) { Html2rss::SST::Normalizer.call(html) }
  let(:html) do
    cards = %w[one two three].map { |slug| %(<article><h2><a href="/news/#{slug}">Story #{slug}</a></h2></article>) }
    <<~HTML
      <html><body>
        <header><a href="/">Home</a><nav><a href="/world/">World desk</a></nav></header>
        <main>
          #{cards.join}
          <article><header><a href="/news/card-header">Card header link</a></header></article>
          <aside><a href="/news/aside-pick">Aside pick</a></aside>
          <menu><li><a href="/news/menu-pick">Menu pick</a></li></menu>
          <a href="#top">Back to top</a>
          <a href="mailto:desk@example.com">Mail the desk</a>
          <a href="http://example.com:abc/">Unresolvable href</a>
        </main>
        <footer><a href="/world/">World desk</a><a href="/news/one">Story one</a><a href="/about/">About</a></footer>
      </body></html>
    HTML
  end

  let(:url_at) { ->(path) { Html2rss::Url.from_absolute("https://example.com#{path}") } }

  describe '.build' do
    it 'is the only constructor' do
      expect { described_class.new(document, link_resolver) }.to raise_error(NoMethodError)
    end

    it 'indexes the document anchors', :aggregate_failures do
      expect(page_links).to be_a(described_class).and be_frozen
      expect(page_links.placement(url_at['/news/one'])).to eq(:content)
    end
  end

  describe '#placement' do
    it 'places relative anchors in sectioned content as content', :aggregate_failures do
      expect(page_links.placement(url_at['/news/two'])).to eq(:content)
      expect(page_links.placement(url_at['/news/card-header'])).to eq(:content)
    end

    it 'places page-level header, nav, and footer anchors as chrome', :aggregate_failures do
      expect(page_links.placement(url_at['/'])).to eq(:chrome)
      expect(page_links.placement(url_at['/world/'])).to eq(:chrome)
      expect(page_links.placement(url_at['/about'])).to eq(:chrome)
    end

    it 'places aside and menu landmark anchors as peripheral', :aggregate_failures do
      expect(page_links.placement(url_at['/news/aside-pick'])).to eq(:peripheral)
      expect(page_links.placement(url_at['/news/menu-pick'])).to eq(:peripheral)
    end

    it 'keeps the strongest placement of a URL rendered in content and chrome' do
      expect(page_links.placement(url_at['/news/one'])).to eq(:content)
    end

    it 'matches URLs by article identity (trailing slash, fragment)', :aggregate_failures do
      expect(page_links.placement(url_at['/news/two/#comments'])).to eq(:content)
      expect(page_links.placement(url_at['/world'])).to eq(:chrome)
    end

    it 'returns :absent for unrendered URLs, skipped hrefs, and nil', :aggregate_failures do
      expect(page_links.placement(url_at['/news/never-rendered'])).to eq(:absent)
      expect(page_links.placement(url_at['/news/?q=1'])).to eq(:absent)
      expect(page_links.placement(nil)).to eq(:absent)
    end

    context 'when structured URLs differ from rendered anchors by scheme or tracking params' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <article><a href="/news/plain">Plain</a></article>
            <article><a href="/news/tracked?utm_source=feed&amp;id=7">Tracked</a></article>
            <article><a href="/news/post?id=1">One</a></article>
            <article><a href="/news/multi?a=1&amp;b=2">Multi</a></article>
            <article><a href="/news/bare?flag">Bare</a></article>
            <article><a href="/news/a?utm_source=hp">Anchor</a></article>
            <article><a href="http://example.com/news/legacy?ref=hp&amp;id=3">Legacy</a></article>
          </main></body></html>
        HTML
      end

      {
        'http://example.com/news/plain' => :content,
        'https://example.com/news/plain?utm_source=x&utm_medium=y' => :content,
        'https://example.com/news/tracked?id=7' => :content,
        'https://example.com/news/post?id=1' => :content,
        'https://example.com/news/post?id=2' => :absent,
        'https://example.com/news/post' => :absent
      }.each do |href, expected|
        it "places #{href} as #{expected}" do
          expect(page_links.placement(Html2rss::Url.from_absolute(href))).to eq(expected)
        end
      end

      it 'exposes the rendered anchor URL as canonical for a variant', :aggregate_failures do
        expect(page_links.canonical_url(Html2rss::Url.from_absolute('http://example.com/news/plain?utm_term=t')).to_s)
          .to eq('https://example.com/news/plain')
        expect(page_links.canonical_url(url_at['/news/tracked?id=7&fbclid=x']).to_s)
          .to eq('https://example.com/news/tracked?id=7')
      end

      it 'strips tracking params from the anchor URL', :aggregate_failures do
        expect(page_links.canonical_url(url_at['/news/a']).to_s).to eq('https://example.com/news/a')
        expect(page_links.canonical_url(url_at['/news/a?utm_source=other']).to_s).to eq('https://example.com/news/a')
      end

      it 'never downgrades an https item to an http anchor', :aggregate_failures do
        expect(page_links.canonical_url(url_at['/news/legacy?id=3']).to_s).to eq('https://example.com/news/legacy?id=3')
        expect(page_links.canonical_url(Html2rss::Url.from_absolute('http://example.com/news/legacy?id=3')).to_s)
          .to eq('http://example.com/news/legacy?id=3')
      end

      it 'has no canonical URL for absent URLs or nil', :aggregate_failures do
        expect(page_links.canonical_url(url_at['/news/post?id=2'])).to be_nil
        expect(page_links.canonical_url(nil)).to be_nil
      end
    end

    context 'when a URL is rendered as chrome, then content, with a fragment' do
      let(:html) do
        '<html><body><nav><a href="/news/x">X</a></nav><main><article><a href="/news/x/#more">X</a></article></main>' \
          '<aside><a href="/news/y">Y</a></aside><nav><a href="/news/z">Z</a></nav></body></html>'
      end

      it 'canonicalizes to the content anchor without its fragment', :aggregate_failures do
        expect(page_links.canonical_url(url_at['/news/x'])).to eq(url_at['/news/x/'])
        expect(page_links.canonical_url(url_at['/news/y'])).to be_nil
        expect(page_links.canonical_url(url_at['/news/z'])).to be_nil
      end
    end

    context 'when a peripheral copy precedes a chrome copy' do
      let(:html) do
        '<html><body><aside><a href="/news/x">X</a></aside><nav><a href="/news/x">X</a></nav></body></html>'
      end

      it 'keeps the stronger peripheral placement' do
        expect(page_links.placement(url_at['/news/x'])).to eq(:peripheral)
      end
    end

    context 'when a chrome copy precedes a peripheral copy' do
      let(:html) do
        '<html><body><nav><a href="/news/x">X</a></nav><aside><a href="/news/x">X</a></aside></body></html>'
      end

      it 'upgrades to the peripheral placement' do
        expect(page_links.placement(url_at['/news/x'])).to eq(:peripheral)
      end
    end

    context 'without a document' do
      let(:document) { nil }
      let(:link_resolver) { nil }

      it 'places every URL as absent' do
        expect(page_links.placement(url_at['/news/one'])).to eq(:absent)
      end
    end
  end

  describe '#sparse?' do
    it 'is false with more than SPARSE_MAX_CONTENT_LINKS content URLs' do
      expect(page_links).not_to be_sparse
    end

    context 'with exactly SPARSE_MAX_CONTENT_LINKS content URLs and many chrome links' do
      let(:html) do
        nav = Array.new(5) { |index| %(<a href="/section-#{index}/">Section #{index}</a>) }.join
        <<~HTML
          <html><body><nav>#{nav}</nav>
            <main><a href="/news/one">One</a><a href="/news/two">Two</a><a href="/news/two/">Two again</a>
            <a href="mailto:desk@example.com">Mail</a><a href="tel:123">Call</a><a href="javascript:void(0)">Do</a>
            <aside><a href="/news/aside">Aside</a></aside></main>
          </body></html>
        HTML
      end

      it 'is true' do
        expect(page_links).to be_sparse
      end
    end

    context 'with no content URLs at all' do
      let(:html) { '<html><body><nav><a href="/world/">World</a></nav><main><p>Text only</p></main></body></html>' }

      it 'is true' do
        expect(page_links).to be_sparse
      end
    end

    context 'without a document' do
      let(:document) { nil }
      let(:link_resolver) { nil }

      it 'is true' do
        expect(page_links).to be_sparse
      end
    end

    context 'with a degraded document' do
      let(:document) do
        Html2rss::SST::Normalizer.call(html).then do |doc|
          Html2rss::SST::Document.build(root: doc.root, index: doc.index, degraded: true, node_count: doc.node_count)
        end
      end

      it 'is true even with many content URLs' do
        expect(page_links).to be_sparse
      end
    end
  end

  describe '#sponsored?' do
    let(:html) do
      <<~HTML
        <html><body><main>
          <article><h3><a href="/news/plain">Plain story</a></h3></article>
          <article><h3><a href="/news/rel-paid" rel="nofollow sponsored">Paid link</a></h3></article>
          <article>
            <a href="/news/labelled"><img src="/a.jpg"></a>
            <h3><a href="/news/labelled#top">Labelled card</a></h3>
            <div><span class="ad-label">Anzeige</span></div>
          </article>
          <article data-advertorial><h3><a href="/news/attributed">Attributed card</a></h3></article>
          <ul>
            <li><a href="/news/listed-one">Listed one</a></li>
            <li class="slot"><span>Advertisement</span></li>
            <li><a href="/news/listed-two">Listed two</a></li>
          </ul>
          <article>
            <h3><a href="/news/mixed-headline">Mixed card</a></h3>
            <a href="/culture/">Culture</a>
            <span>Sponsored</span>
          </article>
          <div><span>Werbung</span><a href="http://example.com:abc/">Unresolvable</a></div>
          <article><h3><a href="/news/after-unresolvable">After unresolvable</a></h3></article>
        </main></body></html>
      HTML
    end

    it 'marks the URL of an anchor whose rel contains sponsored' do
      expect(page_links.sponsored?(url_at['/news/rel-paid'])).to be(true)
    end

    it 'marks the single destination of a card holding an ad label or attribute', :aggregate_failures do
      expect(page_links.sponsored?(url_at['/news/labelled'])).to be(true)
      expect(page_links.sponsored?(url_at['/news/attributed'])).to be(true)
    end

    it 'marks nothing when the marker card spans several destinations', :aggregate_failures do
      expect(page_links.sponsored?(url_at['/news/listed-one'])).to be(false)
      expect(page_links.sponsored?(url_at['/news/listed-two'])).to be(false)
      expect(page_links.sponsored?(url_at['/news/mixed-headline'])).to be(false)
    end

    it 'keeps a marker over unresolvable anchors from reaching later cards' do
      expect(page_links.sponsored?(url_at['/news/after-unresolvable'])).to be(false)
    end

    it 'is false for unmarked, unrendered, and nil URLs', :aggregate_failures do
      expect(page_links.sponsored?(url_at['/news/plain'])).to be(false)
      expect(page_links.sponsored?(url_at['/news/never-rendered'])).to be(false)
      expect(page_links.sponsored?(nil)).to be(false)
    end

    it 'leaves placement unchanged for sponsored URLs' do
      expect(page_links.placement(url_at['/news/rel-paid'])).to eq(:content)
    end
  end
end
