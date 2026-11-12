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

    it 'binds nothing for a label outside every card, even beside a single teaser' do
      expect(page_links.sponsored?(url_at['/news/split-teaser'])).to be(false)
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

    context 'when labels meet cards' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <article><span>Sponsored</span><a href="/news/wrapped-heading"><h3>Wrapped heading</h3></a>
              <a href="/culture/wrapped">Culture</a></article>
            <article><span>Sponsored</span><a href="/news/only-link">Only link</a>
              <div href="/news/stray-href"><p>Stray box</p></div></article>
            <li><div><div><span class="ad-label" aria-hidden="true">Anzeige</span></div></div>
              <a href="/news/deep-label"><img src="/d.jpg"></a><a href="/news/deep-label">Deep label</a></li>
            <article><span>Sponsored</span><a href="/news/beside-bad">Beside bad</a>
              <a href="http://example.com:abc/">Bad</a></article>
            <article><div data-sponsored="true"><img src="/i.jpg"></div>
              <h3><a href="/news/anchorless-container">Anchorless container</a></h3></article>
            <section class="ad-label">Anzeige<h3><a href="/news/labelled-card">Labelled card</a></h3></section>
            <article><span class="label">Sponsored</span><h3><a href="/news/tagged-ad">Tagged ad</a></h3>
              <ul><li><a href="/tag/travel/">Travel</a></li></ul></article>
            <article><a class="ad-label" href="/news/ads-info">Anzeige</a><a href="/news/linked-label">Linked label</a></article>
            <div class="row"><div class="teaser"><h3><a href="/news/row-story">Row story</a></h3></div>
              <div class="ad-box"><span class="ad-label">Anzeige</span><div class="slot"></div></div></div>
            <div class="pair"><div><h2><a href="/news/promoted-story">Promoted story</a></h2></div>
              <div class="promo"><span class="ad-label">Anzeige</span><a href="/news/promoted-story">Listen</a></div></div>
            <article><h3><a href="/news/outer">Outer</a></h3>
              <article><span>Anzeige</span><h3><a href="/news/inner">Inner</a></h3></article></article>
            <span>Anzeige</span>
            <article><span>Sponsored</span><h3><a href="/news/head-one">One</a></h3><h3><a href="/news/head-two">Two</a></h3></article>
            <p><a rel="sponsored" href="/news/head-one">Head one copy</a></p>
            <article><span>Sponsored</span><a href="http://example.com:abc/">Bad</a><h3><a href="/news/after-bad">After</a></h3></article>
            <article><span>Sponsored</span><h3><a href="/news/next-copy">Next copy</a></h3></article><a href="/news/next-copy">Again</a>
          </main></body></html>
        HTML
      end

      let(:sponsored) { ->(*paths) { paths.to_h { [_1, page_links.sponsored?(url_at[_1])] } } }

      it 'marks the dominant destination of the card a label sits in, at any depth' do
        paths = %w[/news/wrapped-heading /news/only-link /news/deep-label /news/beside-bad /news/anchorless-container
                   /news/labelled-card /news/tagged-ad /news/inner /news/after-bad]
        expect(sponsored[*paths, '/culture/wrapped', '/tag/travel/', '/news/outer']).to eq(
          paths.to_h { [_1, true] }.merge('/culture/wrapped' => false, '/tag/travel/' => false, '/news/outer' => false)
        )
      end

      it 'binds nothing for a label outside every card or holding the only other link' do
        paths = %w[/news/row-story /news/promoted-story /news/linked-label /news/ads-info]
        expect(sponsored[*paths]).to eq(paths.to_h { [_1, false] })
      end

      it 'releases a URL whose other copy sits in an unbound card or right after a marked one' do
        paths = %w[/news/head-one /news/head-two /news/next-copy]
        expect(sponsored[*paths]).to eq(paths.to_h { [_1, false] })
      end
    end

    context 'when a label sits inside a card link' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <ul>
              <li><a href="/news/teaser-ad"><div><span>Annons</span></div><h2>Teaser ad</h2></a></li>
              <li><a href="/news/teaser-plain"><h2>Teaser plain</h2></a></li>
              <li><a href="/news/teaser-paid"><div><span>Annons</span></div><h2>Teaser paid</h2></a></li>
            </ul>
            <div class="grid">
              <div><a href="/news/kicker-ad"><img src="/k.jpg"></a>
                <div><a href="/news/kicker-ad"><span class="category">Materiał Partnera</span></a>
                  <a href="/news/kicker-ad"><h3>Kicker ad</h3></a></div></div>
              <div><a href="/topics/politics/"><span class="category">Politics</span></a>
                <a href="/news/kicker-plain"><h3>Kicker plain</h3></a></div>
            </div>
            <div><a href="/news/headingless"><span>Sponsored</span><span>No heading</span></a></div>
            <div><a href="/news/ad-chip"><span class="category">Werbung</span><h3>Ad chip</h3></a></div>
            <div><a href="/news/wrapped-twice"><span>Anzeige</span><h3>One</h3></a><h3>Two</h3></div>
            <p><a href="/news/teaser-ad">Teaser ad, again</a></p>
          </main><footer><ul><li><a href="/mediadaten/"><span>Werbung</span></a></li></ul></footer></body></html>
        HTML
      end

      let(:sponsored) { ->(*paths) { paths.to_h { [_1, page_links.sponsored?(url_at[_1])] } } }

      it 'marks the link destination across its one-card unit when that unit holds a heading' do
        expect(sponsored['/news/kicker-ad', '/news/wrapped-twice', '/news/teaser-paid', '/news/kicker-plain',
                         '/topics/politics/']).to eq(
                           '/news/kicker-ad' => true, '/news/wrapped-twice' => true, '/news/teaser-paid' => true,
                           '/news/kicker-plain' => false, '/topics/politics/' => false
                         )
      end

      it 'binds nothing without a heading, for an ad word on a chip, or in a footer link' do
        paths = %w[/news/headingless /news/ad-chip /mediadaten/ /news/teaser-plain]
        expect(sponsored[*paths]).to eq(paths.to_h { [_1, false] })
      end

      it 'releases a linked destination also rendered outside every marked card' do
        expect(page_links.sponsored?(url_at['/news/teaser-ad'])).to be(false)
      end
    end

    context 'when a linked label sits in the only card of a page' do
      let(:html) do
        '<html><body><div><a href="/news/only"><span>Annons</span><h2>Only story</h2></a></div></body></html>'
      end

      it 'binds the unit at the root' do
        expect(page_links.sponsored?(url_at['/news/only'])).to be(true)
      end
    end

    context 'when a paid label heads a section' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="module"><div class="module__head ad-label"><p>Contenus partenaires</p></div>
              <ul><li><a href="/news/pub-one"><div>Pub one</div></a></li><li><a href="/news/pub-two"><div>Pub two</div></a></li>
                <li><a href="/news/pub-three"><div>Pub three</div></a></li></ul></div>
            <section><h2>Sponsored content</h2>
              <article><h3><a href="/news/rail-one">Rail one</a></h3></article>
              <article><h3><a href="/news/rail-two">Rail two</a></h3></article></section>
            <div class="strip"><span>Materiał partnera</span>
              <div><a href="/news/strip-one"><img src="/1.jpg"></a><h3><a href="/news/strip-one">Strip one</a></h3>
                <a href="mailto:ads@example.com">Mail</a></div>
              <div><a href="/news/strip-two"><img src="/2.jpg"></a><h3><a href="/news/strip-two">Strip two</a></h3></div></div>
            <section><header><span>Sponsored</span><h2>Politics</h2></header>
              <article><h3><a href="/news/desk-one">Desk one</a></h3></article>
              <article><h3><a href="/news/desk-two">Desk two</a></h3></article></section>
            <div class="row"><article><h3><a href="/news/row-one">Row one</a></h3></article>
              <div><p>Sponsored</p></div><article><h3><a href="/news/row-two">Row two</a></h3></article></div>
            <div class="row"><div><span>Anzeige</span></div>
              <article><h3><a href="/news/slot-one">Slot one</a></h3></article>
              <article><h3><a href="/news/slot-two">Slot two</a></h3></article></div>
            <div><article><span>Sponsored</span><h3><a href="/news/heads-one">One</a></h3><h3><a href="/news/heads-two">Two</a></h3></article>
              <article><h3><a href="/news/heads-next">Next</a></h3></article></div>
            <div><p>Sponsored</p><article><h3><a href="/news/lone">Lone</a></h3></article></div>
            <div><p>Sponsored</p><h3>Topic</h3><div><article><h3><a href="/news/topic-a">A</a></h3></article>
              <article><h3><a href="/news/topic-b">B</a></h3></article></div></div>
            <div><p>Sponsored</p><div><article><h3><a href="/news/after-a">A</a></h3></article>
              <article><h3><a href="/news/after-b">B</a></h3></article></div><h3>Topic</h3><p>More</p></div>
            <div><p>Sponsored</p><div><article><h3><a href="/news/aside-a">A</a></h3></article><h4>Aside</h4></div>
              <article><h3><a href="/news/aside-b">B</a></h3></article></div>
            <div><p>Sponsored</p><article><h3><a href="/news/twice">Twice</a></h3><h3><a href="/news/twice">Again</a></h3></article>
              <article><h3><a href="/news/twice-next">Next</a></h3></article></div>
          </main></body></html>
        HTML
      end

      let(:sponsored) { ->(*paths) { paths.to_h { [_1, page_links.sponsored?(url_at[_1])] } } }

      it 'marks every card unit of a section the label opens' do
        paths = %w[/news/pub-one /news/pub-two /news/pub-three /news/rail-one /news/rail-two /news/strip-one
                   /news/strip-two]
        expect(sponsored[*paths]).to eq(paths.to_h { [_1, true] })
      end

      it 'marks no section with its own heading, an anchor before the label, an ad word, or headings as cards' do
        paths = %w[/news/desk-one /news/desk-two /news/row-one /news/row-two /news/slot-one /news/slot-two
                   /news/heads-one /news/heads-two /news/heads-next]
        expect(sponsored[*paths]).to eq(paths.to_h { [_1, false] })
      end

      it 'marks no section with a heading outside its card units at any depth' do
        paths = %w[/news/topic-a /news/topic-b /news/after-a /news/after-b /news/aside-a /news/aside-b
                   /news/twice /news/twice-next]
        expect(sponsored[*paths]).to eq(paths.to_h { [_1, false] })
      end

      it 'marks the one card unit of a bare wrapper the label opens' do
        expect(sponsored['/news/lone']).to eq('/news/lone' => true)
      end
    end

    context 'when a paid label sits in a bare div card or an ad box of a card row' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="row"><div class="c"><span>Sponsored</span><h3><a href="/news/promo">Promo</a></h3></div>
              <div class="c"><h3><a href="/news/row-a">A</a></h3></div><div class="c"><h3><a href="/news/row-b">B</a></h3></div>
              <div class="c"><h3><a href="/news/row-c">C</a></h3></div></div>
            <div class="row"><div class="ad-box"><p>Sponsored</p><div class="slot"></div></div>
              <div class="c"><h3><a href="/news/box-a">A</a></h3></div><div class="c"><h3><a href="/news/box-b">B</a></h3></div></div>
            <div class="row"><div class="ad-box"><p>Sponsored</p><div class="slot"></div></div>
              <div class="c"><h3><a href="/news/trail-a">A</a></h3></div><div class="c"><h3><a href="/news/trail-b">B</a></h3></div>
              <p>More</p><div><div class="c"><h3><a href="/news/trail-c">C</a></h3></div>
                <div class="c"><h3><a href="/news/trail-d">D</a></h3></div></div></div>
            <div class="row"><div class="head"><div><p>Sponsored</p></div></div>
              <div class="c"><h3><a href="/news/head-a">A</a></h3></div><div class="c"><h3><a href="/news/head-b">B</a></h3></div></div>
            <div class="row"><div class="head">Note <p>Sponsored</p></div>
              <div class="c"><h3><a href="/news/note-a">A</a></h3></div><div class="c"><h3><a href="/news/note-b">B</a></h3></div></div>
            <div class="row"><div class="head">Note <div><p>Sponsored</p></div></div>
              <div class="c"><h3><a href="/news/nest-a">A</a></h3></div><div class="c"><h3><a href="/news/nest-b">B</a></h3></div></div>
          </main></body></html>
        HTML
      end

      let(:sponsored) { ->(*paths) { paths.to_h { [_1, page_links.sponsored?(url_at[_1])] } } }

      it 'marks only the card that holds the label' do
        paths = %w[/news/promo /news/row-a /news/row-b /news/row-c]
        expect(sponsored[*paths]).to eq('/news/promo' => true, '/news/row-a' => false, '/news/row-b' => false,
                                        '/news/row-c' => false)
      end

      it 'marks no card beside an ad box or a wrapper holding more than the label' do
        paths = %w[/news/box-a /news/box-b /news/trail-a /news/trail-b /news/trail-c /news/trail-d /news/note-a
                   /news/note-b /news/nest-a /news/nest-b]
        expect(sponsored[*paths]).to eq(paths.to_h { [_1, false] })
      end

      it 'marks the cards beside a wrapper holding only the label' do
        expect(sponsored['/news/head-a', '/news/head-b']).to eq('/news/head-a' => true, '/news/head-b' => true)
      end
    end

    context 'when a paid label binds at its first frame holding a destination' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="promo"><p>Sponsored</p><a href="/news/bare-link">Bare link</a></div>
            <div class="promo"><p>Sponsored</p><h3><a href="/news/dual-a">Dual A</a></h3><a href="/news/dual-b">Dual B</a></div>
            <section><header><span>Sponsored</span><p>Partner picks</p></header>
              <ul><li><h3><a href="/news/list-a">List A</a></h3></li><li><h3><a href="/news/list-b">List B</a></h3></li></ul></section>
            <div class="row"><p>Sponsored</p><h4>Topic</h4><div><article><h3><a href="/news/split-a">A</a></h3></article>
              <article><h3><a href="/news/split-b">B</a></h3></article><h4>Aside</h4></div></div>
            <div class="row"><article><p>Sponsored</p></article>
              <article><h3><a href="/news/past-a">A</a></h3></article><article><h3><a href="/news/past-b">B</a></h3></article></div>
            <div class="row"><img src="/logo.png" alt=""><div><p>Sponsored</p></div>
              <div class="c"><h3><a href="/news/later-a">A</a></h3></div><div class="c"><h3><a href="/news/later-b">B</a></h3></div></div>
          </main></body></html>
        HTML
      end

      let(:sponsored) { ->(*paths) { paths.to_h { [_1, page_links.sponsored?(url_at[_1])] } } }

      it 'marks no lone link without a heading and no card holding two destinations' do
        paths = %w[/news/bare-link /news/dual-a /news/dual-b]
        expect(sponsored[*paths]).to eq(paths.to_h { [_1, false] })
      end

      it 'marks nested card units under a header that holds more than the label' do
        expect(sponsored['/news/list-a', '/news/list-b']).to eq('/news/list-a' => true, '/news/list-b' => true)
      end

      it 'marks no section with headings outside its card units on two levels' do
        expect(sponsored['/news/split-a', '/news/split-b']).to eq('/news/split-a' => false, '/news/split-b' => false)
      end

      it 'stops a label at the card holding it when no destination follows inside that card' do
        expect(sponsored['/news/past-a', '/news/past-b']).to eq('/news/past-a' => false, '/news/past-b' => false)
      end

      it 'finds the wrapper around the label behind an earlier child' do
        expect(sponsored['/news/later-a', '/news/later-b']).to eq('/news/later-a' => true, '/news/later-b' => true)
      end
    end

    context 'when a paid label captions an ad slot' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <div class="row"><p class="ad-caption">Sponsored</p><div class="ad-slot"></div>
              <div class="c"><h3><a href="/news/cap-a">A</a></h3></div><div class="c"><h3><a href="/news/cap-b">B</a></h3></div>
              <div class="c"><h3><a href="/news/cap-c">C</a></h3></div></div>
            <div class="row"><div class="ad"><span>Sponsored</span><div class="slot"></div></div>
              <ul><li><h3><a href="/news/list-a">A</a></h3></li><li><h3><a href="/news/list-b">B</a></h3></li>
                <li><h3><a href="/news/list-c">C</a></h3></li></ul></div>
            <div class="row"><div class="ad"><span>Sponsored</span><ins class="slot"></ins></div>
              <article><h3><a href="/news/one">One</a></h3></article></div>
            <div class="row"><div class="ad"><div class="slot"><div></div></div><span>Sponsored</span></div>
              <article><h3><a href="/news/below-a">A</a></h3></article><article><h3><a href="/news/below-b">B</a></h3></article></div>
            <div class="module"><div class="module__head"><span>Sponsored</span><div class="logo"><img src="/l.png" alt=""></div></div>
              <ul><li><h3><a href="/news/paid-a">A</a></h3></li><li><h3><a href="/news/paid-b">B</a></h3></li></ul></div>
            <div class="module"><div class="module__head"><span>Sponsored</span><i class="info"></i></div>
              <ul><li><h3><a href="/news/icon-a">A</a></h3></li><li><h3><a href="/news/icon-b">B</a></h3></li></ul></div>
          </main></body></html>
        HTML
      end

      let(:sponsored) { ->(*paths) { paths.to_h { [_1, page_links.sponsored?(url_at[_1])] } } }

      it 'marks no card after an empty slot beside the label or its wrapper' do
        paths = %w[/news/cap-a /news/cap-b /news/cap-c /news/list-a /news/list-b /news/list-c /news/one
                   /news/below-a /news/below-b]
        expect(sponsored[*paths]).to eq(paths.to_h { [_1, false] })
      end

      it 'marks the cards under a header holding a sponsor logo or an icon beside the label' do
        paths = %w[/news/paid-a /news/paid-b /news/icon-a /news/icon-b]
        expect(sponsored[*paths]).to eq(paths.to_h { [_1, true] })
      end
    end

    context 'when a paid label opens a page region' do
      let(:html) do
        <<~HTML
          <html><body><p>Sponsored</p><main>
            <article><h3><a href="/news/page-one">One</a></h3></article>
            <article><h3><a href="/news/page-two">Two</a></h3></article>
          </main></body></html>
        HTML
      end

      it 'marks nothing', :aggregate_failures do
        expect(page_links.sponsored?(url_at['/news/page-one'])).to be(false)
        expect(page_links.sponsored?(url_at['/news/page-two'])).to be(false)
      end
    end

    context 'when wrappers contain or hide markers' do
      let(:html) do
        <<~HTML
          <html><body><main>
            <ul class="has-sponsored">
              <li><h3><a href="/news/editorial">Editorial</a></h3></li>
              <li class="is-sponsored"><h3><a href="/news/paid">Paid</a></h3></li>
            </ul>
            <article><div class="d-none"><span>Anzeige</span></div><h3><a href="/news/hidden-label">Hidden</a></h3></article>
            <article><div hidden><span class="ad-label">Anzeige</span></div><h3><a href="/news/hidden-badge">Badge</a></h3></article>
            <article><div style="display:none"><p><span>Werbung</span></p></div><h3><a href="/news/hidden-deep">Deep</a></h3></article>
            <div class="hide"><article><span>Anzeige</span><h3><a href="/news/hidden-panel">Panel</a></h3></article></div>
          </main></body></html>
        HTML
      end

      let(:sponsored) { ->(*paths) { paths.to_h { [_1, page_links.sponsored?(url_at[_1])] } } }

      it 'reads a has- wrapper as containing sponsored cards, not as one' do
        expect(sponsored['/news/editorial', '/news/paid']).to eq('/news/editorial' => false, '/news/paid' => true)
      end

      it 'ignores labels under a hidden ancestor inside their card, but not a hidden region around the card' do
        expect(sponsored['/news/hidden-label', '/news/hidden-badge', '/news/hidden-deep', '/news/hidden-panel']).to eq(
          '/news/hidden-label' => false, '/news/hidden-badge' => false, '/news/hidden-deep' => false,
          '/news/hidden-panel' => true
        )
      end
    end

    context 'without markers' do
      let(:html) { '<html><body><article><h3><a href="/news/plain">Plain</a></h3></article></body></html>' }

      it 'resolves no anchor', :aggregate_failures do
        allow(link_resolver).to receive(:destination_facts).and_call_original
        expect(page_links.sponsored?(url_at['/news/plain'])).to be(false)
        expect(link_resolver).not_to have_received(:destination_facts)
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
