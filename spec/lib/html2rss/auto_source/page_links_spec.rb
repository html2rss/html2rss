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
          <article data-advertorial="true"><h3><a href="/news/attributed">Attributed card</a></h3></article>
          <article data-advertorial=""><h3><a href="/news/blank-attribute">Blank attribute card</a></h3></article>
          <article>
            <div><span>Sponsored</span></div>
            <div><span aria-label="Anzeige"></span></div>
            <h3><a href="/news/twice-labelled">Twice labelled card</a></h3>
          </article>
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
          <div class="row">
            <div class="ad-slot"><span>Anzeige</span></div>
            <article><h3><a href="/news/beside-slot">Beside an empty ad slot</a></h3></article>
          </div>
          <div class="row"><p>Advertisement</p><article><h3><a href="/news/beside-label">Beside a label</a></h3></article></div>
          <div class="row"><article><span>Sponsored</span></article><a href="/news/after-empty-card">After an empty card</a></div>
          <div data-sponsored="yes"><article><h3><a href="/news/wrapped">Wrapped card</a></h3></article></div>
          <section aria-label="Anzeige">
            <article><h3><a href="/news/rail-one">Rail one</a></h3></article>
            <article><h3><a href="/news/rail-two">Rail two</a></h3><a href="/sport/">Sport</a></article>
          </section>
          <div class="list">
            <div class="teaser--advertorial"><h3><a href="/news/bem-one">BEM one</a></h3></div>
            <div class="teaser"><h3><a href="/news/bem-neighbour">BEM neighbour</a></h3></div>
          </div>
          <article>
            <span class="label">Sponsored</span>
            <a href="/news/dominant?src=img"><img src="/d.jpg"></a>
            <a class="ad-label" href="/about-ads/">Anzeige</a>
            <h3><a href="/news/dominant">Dominant headline</a></h3>
            <p>Presented by <a href="https://brand.example.com/">Acme</a></p>
          </article>
          <div class="grid">
            <div><h3><a href="/news/grid-one">Grid one</a></h3></div>
            <span>Anzeige</span>
            <div><h3><a href="/news/grid-two">Grid two</a></h3></div>
          </div>
          <div class="teaser">
            <div class="media"><a href="/news/split-teaser"><img src="/s.jpg"></a><div><span>Anzeige</span></div></div>
            <header><h3><a href="/news/split-teaser">Split teaser</a></h3></header>
            <section><a href="/news/split-teaser">Teaser text</a></section>
          </div>
          <article><h3><a href="/news/house-story">House story</a></h3></article>
          <aside><span class="ad-label">Anzeige</span><a href="/news/house-story">Listen to our podcast</a></aside>
          <article><h3><a href="/news/in-heading">Why <em>sponsored</em> posts win</a></h3></article>
          <article>
            <h3><a href="/news/review">Review</a></h3>
            <p>Buy it: <a rel="sponsored" href="https://shop.example.com/buy">at the shop</a></p>
          </article>
          <article>
            <span>Sponsored</span>
            <h3><a href="/news/beside-skipped">Beside skipped hrefs</a></h3>
            <a href="mailto:ads@example.com">Mail</a><a href="http://example.com:abc/">Unresolvable</a>
          </article>
        </main></body></html>
      HTML
    end

    it 'marks the URL of an anchor whose rel contains sponsored' do
      expect(page_links.sponsored?(url_at['/news/rel-paid'])).to be(true)
    end

    it 'marks the single destination of a card holding an ad label or attribute', :aggregate_failures do
      expect(page_links.sponsored?(url_at['/news/labelled'])).to be(true)
      expect(page_links.sponsored?(url_at['/news/attributed'])).to be(true)
      expect(page_links.sponsored?(url_at['/news/twice-labelled'])).to be(true)
    end

    it 'marks nothing when a label sits between several headline destinations', :aggregate_failures do
      expect(page_links.sponsored?(url_at['/news/listed-one'])).to be(false)
      expect(page_links.sponsored?(url_at['/news/listed-two'])).to be(false)
      expect(page_links.sponsored?(url_at['/news/grid-one'])).to be(false)
      expect(page_links.sponsored?(url_at['/news/grid-two'])).to be(false)
    end

    it "marks a labelled card's headline beside secondary links", :aggregate_failures do
      expect(page_links.sponsored?(url_at['/news/mixed-headline'])).to be(true)
      expect(page_links.sponsored?(url_at['/news/dominant'])).to be(true)
      expect(page_links.sponsored?(url_at['/culture/'])).to be(false)
    end

    it 'marks every card inside an explicit container marker', :aggregate_failures do
      expect(page_links.sponsored?(url_at['/news/rail-one'])).to be(true)
      expect(page_links.sponsored?(url_at['/news/rail-two'])).to be(true)
      expect(page_links.sponsored?(url_at['/sport/'])).to be(true)
      expect(page_links.sponsored?(url_at['/news/bem-one'])).to be(true)
      expect(page_links.sponsored?(url_at['/news/bem-neighbour'])).to be(false)
    end

    it 'keeps a URL that an unmarked card also links' do
      expect(page_links.sponsored?(url_at['/news/house-story'])).to be(false)
    end

    it 'widens a bound card over sibling wrappers linking only its destination' do
      expect(page_links.sponsored?(url_at['/news/split-teaser'])).to be(true)
    end

    it 'marks only the sponsored link itself for rel, never its card', :aggregate_failures do
      expect(page_links.sponsored?(url_at['/news/review'])).to be(false)
      expect(Html2rss::Url.from_absolute('https://shop.example.com/buy').then { page_links.sponsored?(_1) }).to be(true)
    end

    it 'ignores a switched-off attribute and a label inside a headline', :aggregate_failures do
      expect(page_links.sponsored?(url_at['/news/blank-attribute'])).to be(false)
      expect(page_links.sponsored?(url_at['/news/in-heading'])).to be(false)
    end

    it 'keeps a marker over unresolvable anchors from reaching later cards' do
      expect(page_links.sponsored?(url_at['/news/after-unresolvable'])).to be(false)
    end

    it 'never binds a marker to a sibling card it is not inside of', :aggregate_failures do
      expect(page_links.sponsored?(url_at['/news/beside-slot'])).to be(false)
      expect(page_links.sponsored?(url_at['/news/beside-label'])).to be(false)
    end

    it 'stops a marker at its own card boundary when that card holds no anchor' do
      expect(page_links.sponsored?(url_at['/news/after-empty-card'])).to be(false)
    end

    it 'marks the single card inside a marked wrapper' do
      expect(page_links.sponsored?(url_at['/news/wrapped'])).to be(true)
    end

    it 'ignores skipped and unresolvable hrefs when counting card destinations' do
      expect(page_links.sponsored?(url_at['/news/beside-skipped'])).to be(true)
    end

    it 'is false for unmarked, unrendered, and nil URLs', :aggregate_failures do
      expect(page_links.sponsored?(url_at['/news/plain'])).to be(false)
      expect(page_links.sponsored?(url_at['/news/never-rendered'])).to be(false)
      expect(page_links.sponsored?(nil)).to be(false)
    end

    it 'leaves placement unchanged for sponsored URLs' do
      expect(page_links.placement(url_at['/news/rel-paid'])).to eq(:content)
    end

    context 'when markers meet bound cards inside one wrapper' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <article><span>Sponsored</span><a href="/news/wrapped-heading"><h3>Wrapped heading</h3></a>
              <a href="/culture/wrapped">Culture</a></article>
            <article><span>Sponsored</span><a href="/news/only-link">Only link</a>
              <div href="/news/stray-href"><p>Stray box</p></div></article>
            <article><span>Sponsored</span><a href="/news/duplicate"><img src="/d.jpg"></a>
              <a href="/news/duplicate">Duplicate</a></article>
            <article><span>Sponsored</span><a href="/news/beside-bad">Beside bad</a>
              <a href="http://example.com:abc/">Bad</a></article>
            <article><div data-sponsored="true"><img src="/i.jpg"></div>
              <h3><a href="/news/anchorless-container">Anchorless container</a></h3></article>
            <article><a class="ad-label" href="/news/ads-info">Anzeige</a><a href="/news/linked-label">Linked label</a></article>
            <article><div class="grid"><a href="/news/grid-paid">Grid paid</a><span>Anzeige</span>
              <a href="/news/grid-free">Grid free</a></div><h3><a href="/news/grid-outer">Grid outer</a></h3></article>
            <p><a rel="sponsored" href="/news/grid-paid">Grid paid copy</a></p>
            <div><article><p><a class="ad-label" href="/news/own-label">Anzeige</a></p></article></div>
            <p><a rel="sponsored" href="/news/own-label">Own label copy</a></p>
            <div><div><span>Anzeige</span><a href="/news/twin"><img src="/t.jpg"></a></div>
              <div><span>Anzeige</span><h3><a href="/news/twin">Twin</a></h3></div><a href="/news/twin">Twin again</a></div>
            <div><div><div><span>Anzeige</span><a href="/news/two-level">Two level</a></div>
              <a href="/news/two-level">Inner copy</a></div><a href="/news/two-level">Outer copy</a></div>
            <div><div><span>Anzeige</span><a href="/news/narrow">Narrow</a></div>
              <a href="/news/narrow-other">Other</a><a href="/news/narrow">Narrow again</a></div>
            <div><section aria-label="Anzeige"><a href="/news/rail-a">Rail A</a><a href="/news/rail-b">Rail B</a></section>
              <a href="/news/rail-a">Rail A again</a></div>
            <div><div><span>Anzeige</span><a href="/news/pair-one">Pair one</a></div>
              <div><span>Anzeige</span><a href="/news/pair-two">Pair two</a></div>
              <h3><a href="/news/pair-head">Pair head</a></h3></div>
            <div><div><span>Sponsored</span></div><div><span>Anzeige</span><a href="/news/label-first-card">Card</a></div>
              <h3><a href="/news/label-first-head">Label first head</a></h3></div>
            <div><div><span>Anzeige</span><a href="/news/card-first-card">Card</a></div><div><span>Sponsored</span></div>
              <h3><a href="/news/card-first-head">Card first head</a></h3></div>
            <div><article><span>Sponsored</span></article><div><span>Anzeige</span><a href="/news/empty-card">Card</a></div>
              <a href="/news/empty-card">Card again</a></div>
            <div><section class="ad-label">Anzeige</section><div><span>Anzeige</span><a href="/news/label-card">Card</a></div>
              <a href="/news/label-card">Card again</a></div>
            <div><div><p>Advertisement</p><article><p>Not a card</p></article></div>
              <div><span>Anzeige</span><a href="/news/enclosed-label">Card</a></div>
              <a href="/news/enclosed-label">Card again</a></div>
          </main></body></html>
        HTML
      end

      let(:sponsored) { ->(*paths) { paths.to_h { [_1, page_links.sponsored?(url_at[_1])] } } }

      it 'binds a label to its single card destination, ignoring stray, duplicate and unresolvable hrefs' do
        paths = %w[/news/wrapped-heading /news/only-link /news/duplicate /news/beside-bad /news/anchorless-container
                   /news/linked-label]
        expect(sponsored[*paths, '/culture/wrapped', '/news/ads-info']).to eq(
          paths.to_h { [_1, true] }.merge('/culture/wrapped' => false, '/news/ads-info' => false)
        )
      end

      it 'releases a URL whose other copy sits in an unbound card or a label' do
        paths = %w[/news/grid-paid /news/grid-outer /news/own-label]
        expect(sponsored[*paths]).to eq(paths.to_h { [_1, false] })
      end

      it 'widens a bound card only over copies of its own destination' do
        expect(sponsored['/news/twin', '/news/two-level', '/news/narrow', '/news/rail-a', '/news/rail-b']).to eq(
          '/news/twin' => true, '/news/two-level' => true, '/news/narrow' => false,
          '/news/rail-a' => false, '/news/rail-b' => true
        )
      end

      it 'lets a waiting label beside a bound card bind the shared headline' do
        expect(sponsored['/news/label-first-head', '/news/card-first-head', '/news/pair-head']).to eq(
          '/news/label-first-head' => true, '/news/card-first-head' => true, '/news/pair-head' => false
        )
      end

      it 'keeps a label stopped at its card boundary from blocking a sibling card that widens' do
        paths = %w[/news/empty-card /news/label-card /news/enclosed-label]
        expect(sponsored[*paths]).to eq(paths.to_h { [_1, true] })
      end
    end

    context 'without a document' do
      let(:document) { nil }
      let(:link_resolver) { nil }

      it 'is false' do
        expect(page_links.sponsored?(url_at['/news/plain'])).to be(false)
      end
    end
  end
end
