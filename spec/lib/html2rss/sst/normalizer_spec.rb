# frozen_string_literal: true

RSpec.describe Html2rss::SST::Normalizer do
  describe '.call' do
    let(:simple_html) do
      <<~HTML
        <html><body>
          <script>evil()</script>
          <article class="card teaser"><a href="/p">Post</a></article>
        </body></html>
      HTML
    end

    it 'strips script tags from the tree' do
      doc = described_class.call(simple_html, vocabulary: all_scope)
      expect(doc.root.find { |n| n.name == :script }).to be_nil
    end

    it 'keeps a noscript only as the file links inside it, as chrome with invisible text', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      doc = described_class.call('<html><body><article><h2>Episode</h2><noscript><p>Listen <a href="/a.mp3">Get</a>' \
                                 '<a href="/page">Page</a><img src="/i.jpg"></p></noscript></article></body></html>',
                                 vocabulary: all_scope)
      noscript = doc.root.find { |n| n.name == :noscript }

      expect(noscript.children.map { [_1.name, _1.attrs.href] }).to eq([[:a, '/a.mp3']])
      expect(doc.index.ignored_chrome?(noscript.children.first)).to be(true)
      expect(Html2rss::SST::Text.extract(doc.index.parent_of(noscript))).to eq('Episode')
    end

    it 'strips other hidden containers even when they hold file links' do
      doc = described_class.call('<html><body><p>x</p><template><a href="/t.mp3">T</a></template>' \
                                 '<svg><a href="/s.mp3">S</a></svg></body></html>', vocabulary: all_scope)

      expect(doc.root.find_all { |n| n.name != :html && n.name != :body && n.name != :p }).to be_empty
    end

    it 'strips a noscript without file links', :aggregate_failures do
      doc = described_class.call('<html><body><p>x</p><noscript><a href="/page">Page</a><img src="/i.jpg">' \
                                 '</noscript></body></html>', vocabulary: all_scope)

      expect(doc.root.find { |n| n.name == :noscript }).to be_nil
      expect(doc.node_count).to eq(3)
    end

    it 'builds typed Attrs on nodes', :aggregate_failures do
      doc = described_class.call(simple_html, vocabulary: all_scope)
      article = doc.root.find { |n| n.name == :article }

      expect(article.attrs).to be_a(Html2rss::SST::Attrs)
      expect(article.attrs.class_names).to include('card', 'teaser')
    end

    it 'maps typed attributes and keeps only allowlisted raw attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = '<html><body><div id="i" class=" a  b " datetime="2020" itemprop="x" style="c:d" srcset="s 1x" ' \
             'type="t" data-k="v" aria-label="L" role="r" width="3" onclick="x">q</div></body></html>'
      div = described_class.call(html, vocabulary: all_scope).root.find { |n| n.name == :div }

      expect(div.attrs.to_h).to eq(
        href: nil, src: nil, id: 'i', class_names: %w[a b], datetime: '2020', itemprop: 'x', style: 'c:d',
        srcset: 's 1x', type: 't', raw: { 'data-k' => 'v', 'aria-label' => 'L', 'role' => 'r' }
      )
    end

    it 'keeps hidden and aria-hidden for sponsorship markers but no attribute that only starts with hidden' do
      html = '<html><body><span class="ad-label" hidden aria-hidden="true" hiddenx="1">q</span></body></html>'
      span = described_class.call(html, vocabulary: all_scope).root.find { |n| n.name == :span }

      expect(span.attrs.raw).to eq('hidden' => '', 'aria-hidden' => 'true')
    end

    it 'keeps rel for sponsorship markers but no attribute that only starts with rel' do
      html = '<html><body><a href="/x" rel="sponsored nofollow" release="1">q</a></body></html>'
      link = described_class.call(html, vocabulary: all_scope).root.find { |n| n.name == :a }

      expect(link.attrs.raw).to eq('rel' => 'sponsored nofollow')
    end

    it 'maps href and src onto typed attrs', :aggregate_failures do
      doc = described_class.call('<html><body><a href="/post">Post</a><img src="/cover.png"></body></html>',
                                 vocabulary: all_scope)

      expect(doc.root.find { |n| n.name == :a }.attrs.href).to eq('/post')
      expect(doc.root.find { |n| n.name == :img }.attrs.src).to eq('/cover.png')
    end

    it 'does not copy typed attributes into the raw hash' do
      link = described_class.call('<html><body><a href="/x" id="y">q</a></body></html>', vocabulary: all_scope).root
                            .find { |n| n.name == :a }

      expect(link.attrs.raw).to eq({})
    end

    it 'splits class names on any whitespace and keeps none for a blank attribute', :aggregate_failures do
      html = "<html><body><p class=\"a\tb\nc\">x</p><p class=\" \">y</p></body></html>"
      spaced, blank = described_class.call(html, vocabulary: all_scope).root.find_all { |n| n.name == :p }

      expect(spaced.attrs.class_names).to eq(%w[a b c])
      expect(blank.attrs.class_names).to eq([])
    end

    it 'freezes the class tokens and raw attributes it keeps', :aggregate_failures do
      html = '<html><body><p class="a b" data-k="v">x</p></body></html>'
      attrs = described_class.call(html, vocabulary: all_scope).root.find { |n| n.name == :p }.attrs

      expect([attrs.class_names, *attrs.class_names, attrs.raw, *attrs.raw.values]).to all(be_frozen)
      expect(attrs.raw).to eq('data-k' => 'v')
    end

    it 'gives an element without attributes the shared empty attrs', :aggregate_failures do
      html = '<html><body><p>x</p><p onclick="x">y</p></body></html>'
      bare, unkept = described_class.call(html, vocabulary: all_scope).root.find_all { |n| n.name == :p }

      expect(bare.attrs).to be(Html2rss::SST::Attrs.empty)
      expect(unkept.attrs).to eq(Html2rss::SST::Attrs.empty)
    end

    it 'passes the tag it already holds to the chrome scope rule' do
      allow(Html2rss::SST::Tags).to receive(:chrome_scope).and_call_original

      described_class.call('<html><body><nav></nav></body></html>', vocabulary: all_scope)

      expect(Html2rss::SST::Tags).to have_received(:chrome_scope)
        .with(kind_of(Nokogiri::XML::Element), :page, all_scope, 'nav')
    end

    it 'keeps the scope of a node apart from an equal node elsewhere', :aggregate_failures do
      html = '<html><body><div role="navigation"><p>a</p></div><div><p>a</p></div></body></html>'
      document = described_class.call(html, vocabulary: all_scope)
      chrome, plain = document.root.find_all { _1.name == :p }

      expect(chrome).to eq(plain)
      expect([chrome, plain].map { document.index.ignored_chrome?(_1) }).to eq([true, false])
    end

    it 'logs which root fallback was used', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(Html2rss::Log).to receive(:warn)
      fallback = lambda do |reason, message|
        { event_name: 'sst.normalizer.root_fallback', reason:, message: }.to_json
      end

      described_class.call(Nokogiri::XML('<root><body><p>x</p></body></root>'), vocabulary: all_scope)
      expect(Html2rss::Log).to have_received(:warn)
        .with(fallback.call('body', 'sst.normalizer root fallback: body'))

      described_class.call(Nokogiri::XML('<root><div>x</div></root>'), vocabulary: all_scope)
      expect(Html2rss::Log).to have_received(:warn)
        .with(fallback.call('first_element_child', 'sst.normalizer root fallback: first element child'))
    end

    it 'returns nil when the parsed input has no element to root the tree', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(Html2rss::Log).to receive(:warn)

      expect(described_class.call(Nokogiri::XML('<!-- c -->'), vocabulary: all_scope)).to be_nil
      expect(Html2rss::Log).to have_received(:warn).with(
        { event_name: 'sst.normalizer.root_fallback', reason: 'self',
          message: 'sst.normalizer root fallback: self' }.to_json
      )
    end

    it 'indexes the exact parent instance even for structurally identical siblings', # rubocop:disable RSpec/ExampleLength
       :aggregate_failures do
      doc = described_class.call('<html><body><div><p>x</p></div><div><p>x</p></div></body></html>',
                                 vocabulary: all_scope)
      body = doc.root.find { |n| n.name == :body }
      first_div, second_div = body.children

      expect(doc.index.parent_of(first_div.children.first)).to equal(first_div)
      expect(doc.index.parent_of(second_div.children.first)).to equal(second_div)
    end

    it 'does not log a root fallback for a regular html document' do
      allow(Html2rss::Log).to receive(:warn)

      described_class.call('<html><body><p>x</p></body></html>', vocabulary: all_scope)
      expect(Html2rss::Log).not_to have_received(:warn)
    end

    it 'indexes parent relationships' do
      doc = described_class.call(simple_html, vocabulary: all_scope)
      article = doc.root.find { |n| n.name == :article }
      expect(doc.index.parent_of(article.children.first)).to eq(article)
    end

    it 'accepts an already-parsed Nokogiri node without re-wrapping' do
      node = Nokogiri::HTML(simple_html)
      expect(described_class.call(node, vocabulary: all_scope).root.find { |n| n.name == :article }).not_to be_nil
    end

    it 'normalizes HTML fragments from the first element child', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      fragment = Nokogiri::HTML.fragment('<article><a href="/p">Post</a></article>')
      allow(Html2rss::Log).to receive(:warn)

      doc = described_class.call(fragment, vocabulary: all_scope)

      expect(doc.root.name).to eq(:article)
      expect(doc.root.find { |n| n.name == :a }).not_to be_nil
      expect(Html2rss::Log).to have_received(:warn).with(/first element child/)
    end

    it 'normalizes script-only body nodes from the body root', :aggregate_failures do
      body = Nokogiri::HTML('<html><body><script>evil()</script></body></html>').at_css('body')
      allow(Html2rss::Log).to receive(:warn)

      doc = described_class.call(body, vocabulary: all_scope)

      expect(doc.root.name).to eq(:body)
      expect(Html2rss::Log).to have_received(:warn).with(/root fallback: self/)
    end

    it 'degrades when MAX_NODES is breached', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      stub_const('Html2rss::SST::Normalizer::MAX_NODES', 3)
      allow(Html2rss::Log).to receive(:warn)

      html = '<html><body><div><div><div><p>x</p></div></div></div></body></html>'
      doc = described_class.call(html, vocabulary: all_scope)

      expect(doc.degraded).to be(true)
      expect(Html2rss::Log).to have_received(:warn).with(
        {
          event_name: 'sst.normalizer.max_nodes',
          max_nodes: 3,
          message: 'sst.normalizer MAX_NODES=3 breached; degrading to semantic-tag-only'
        }.to_json
      )
    end

    it 'drops non-semantic tags once the node ceiling is reached', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      stub_const('Html2rss::SST::Normalizer::MAX_NODES', 1)
      allow(Html2rss::Log).to receive(:warn)
      doc = described_class.call('<html><body><span>x</span><p>y</p></body></html>', vocabulary: all_scope)

      expect(doc.degraded).to be(true)
      expect(doc.root.find { |node| node.name == :span }).to be_nil
      expect(doc.root.find { |node| node.name == :p }).not_to be_nil
    end

    it 'degrades on the node that reaches the ceiling' do
      stub_const('Html2rss::SST::Normalizer::MAX_NODES', 2)
      allow(Html2rss::Log).to receive(:warn)

      doc = described_class.call('<html><body><article>x</article></body></html>', vocabulary: all_scope)

      expect(doc.degraded).to be(true)
    end

    it 'records path, depth, chrome, text, and node count', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = '<html><body><header><a href="/home">Home</a></header><article><p>Post</p></article></body></html>'
      doc = described_class.call(html, vocabulary: all_scope)
      header = doc.root.find { |node| node.name == :header }
      article = doc.root.find { |node| node.name == :article }
      paragraph = article.children.first

      expect(doc.node_count).to eq(6)
      expect(doc.index.depth_of(doc.root)).to eq(0)
      expect(doc.index.parent_of(doc.root)).to be_nil
      expect(doc.index.depth_of(paragraph)).to eq(3)
      expect(doc.index.parent_of(paragraph)).to eq(article)
      expect(paragraph.tag_path).to eq('/html/body/article/p')
      expect(paragraph.own_text).to eq('Post')
      expect(doc.index.ignored_chrome?(header)).to be(true)
      expect(doc.index.ignored_chrome?(header.children.first)).to be(true)
      expect(doc.index.ignored_chrome?(article)).to be(false)

      text = Nokogiri::HTML.fragment('just text').child
      expect(described_class.call(text, vocabulary: all_scope)).to be_nil
    end

    %w[article section aside main].each do |section|
      it "keeps header, its link, and footer inside #{section} out of chrome" do # rubocop:disable RSpec/ExampleLength
        doc = described_class.call("<html><body><#{section}><header><a href=\"/p\">P</a></header>" \
                                   "<footer>F</footer></#{section}></body></html>", vocabulary: all_scope)
        header = doc.root.find { _1.name == :header }
        nodes = [header, header.children.first, doc.root.find { _1.name == :footer }]
        chrome = nodes.map { doc.index.ignored_chrome?(_1) }

        expect(chrome).to eq([false, false, false])
      end
    end

    it 'keeps page-level header and footer as chrome', :aggregate_failures do
      doc = described_class.call('<html><body><header>H</header><div><footer>F</footer></div></body></html>',
                                 vocabulary: all_scope)

      expect(doc.index.ignored_chrome?(doc.root.find { _1.name == :header })).to be(true)
      expect(doc.index.ignored_chrome?(doc.root.find { _1.name == :footer })).to be(true)
    end

    it 'keeps chrome for headers under a page-level nav or footer', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      doc = described_class.call('<html><body><div><nav><header id="n">N</header></nav></div><footer>' \
                                 '<article><header id="f"><a href="/f">F</a></header></article></footer></body></html>',
                                 vocabulary: all_scope)
      chrome = %w[n f].map { |id| doc.index.ignored_chrome?(doc.root.find { _1.attrs.id == id }) }

      expect(chrome).to eq([true, true])
      expect(doc.index.ignored_chrome?(doc.root.find(&:link?))).to be(true)
    end

    it 'scopes nav and ARIA roles like header/footer, keeping pagers chrome' do # rubocop:disable RSpec/ExampleLength
      doc = described_class.call(<<~HTML, vocabulary: all_scope)
        <html><body>
          <div role="navigation"><a id="role_nav" href="/a">A</a></div>
          <div role="Dialog Alert"><a id="role_dialog" href="/b">B</a></div>
          <div role="banner"><a id="page_banner" href="/c">C</a></div>
          <div role="search"><a id="search" href="/d">D</a></div>
          <main>
            <nav aria-label="Latest"><a id="main_nav" href="/e">E</a></nav>
            <div role="contentinfo"><a id="main_contentinfo" href="/f">F</a></div>
            <nav><a id="rel_pager" rel="prev" href="/g">G</a></nav>
            <nav aria-label="Page navigation"><a id="nav_page_nav" href="/h">H</a></nav>
            <ol aria-label="Pagination"><li><a id="list_pager" href="/i">2</a></li></ol>
            <ul><li><a id="list_rel" rel="next" href="/j">J</a></li></ul>
            <nav class="gsc-pagination"><a id="class_pager" href="/k">K</a></nav>
            <ul class="paginated-list"><li><a id="paginated_list" href="/l">L</a></li></ul>
            <div class="pagination" aria-label="Pagination"><a id="div_pager" href="/m?page=2">2</a></div>
          </main>
        </body></html>
      HTML
      chrome = doc.root.find_all(&:link?).to_h { [_1.attrs.id, doc.index.ignored_chrome?(_1)] }

      expect(chrome).to eq('role_nav' => true, 'role_dialog' => true, 'page_banner' => true, 'search' => false,
                           'main_nav' => false, 'main_contentinfo' => false, 'rel_pager' => true,
                           'nav_page_nav' => true, 'list_pager' => true, 'list_rel' => false,
                           'class_pager' => true, 'paginated_list' => false, 'div_pager' => false)
    end

    {
      '<ul class="pagination"><li><a href="/news/?page=2">Older</a></li></ul>' => true,
      '<ul class="Pager"><li><a href="/s">Story one</a></li><li><a href="/news/page/3">More</a></li></ul>' => true,
      '<ul class="paging"><li><a href="/a">Next</a></li><li><a href="/b">«</a></li></ul>' => true,
      '<ol aria-label="Paginación"><li><a rel="Prev" href="/a">Atrás</a></li></ol>' => true,
      '<ul class="pagination"><li><a href="/a">Story one</a></li><li><a href="/b">Story two</a></li></ul>' => false,
      '<ul class="pagination"></ul>' => false,
      '<ul class="pagination"><li><a href="/a">2</a></li><li><a>B</a></li><li><a>C</a></li></ul>' => false,
      '<ul class="pagination"><li><a href="/a"> 2 </a></li><li><a>Story</a></li></ul>' => true,
      '<ul class="pagination"><li><a href="/a" data-next="/page/3">Story</a></li></ul>' => false,
      '<nav><a href="/a">The pager returns</a></nav>' => false,
      '<ul aria-label="Paginated list of articles"><li><a href="/news/?page=2">2</a></li></ul>' => false,
      '<ul class="teaser-list js-pagination-container"><li><a href="/x?page=2">2</a></li></ul>' => false,
      '<ol class="list paging-container"><li><a href="/x?page=2">2</a></li></ol>' => false,
      '<ul class="list infinite-pager"><li><a href="/x?page=2">2</a></li></ul>' => false,
      '<ul><li><a href="/x?page=2">2</a></li></ul>' => false,
      '<nav aria-label="Paginated list of articles"><a href="/a">A</a></nav>' => false,
      '<nav class="gsc-pagination" aria-label="Select a page"><a href="/a">A</a></nav>' => true,
      '<ul class="pagination"><li><a href="/a">Suivant »</a></li></ul>' => true,
      '<ul class="pagination"><li><a href="/a">« Précédent</a></li></ul>' => true,
      '<ul class="pagination"><li><a href="/a">次へ</a></li></ul>' => true,
      '<ul class="pagination"><li><a href="/a">Página siguiente</a></li></ul>' => true,
      '<ul class="pagination"><li><a href="/a">Nächste Seite</a></li></ul>' => true,
      '<ul class="pagination"><li><a href="/a">Vorige pagina</a></li></ul>' => true,
      '<ul class="pagination"><li><a href="/a">Poprzednia strona</a></li></ul>' => true,
      '<ul class="pagination"><li><a href="/a">Nästa sida</a></li></ul>' => true,
      '<ul class="pagination"><li><a href="/a">Pagina successiva</a></li></ul>' => true,
      '<ul class="pagination"><li><a href="/a">Próxima página</a></li></ul>' => true,
      '<ul class="pagination"><li><a href="/a">PRÉCÉDENT</a></li></ul>' => true,
      '<ul class="pagination"><li><a href="/a">Suivant le match</a></li></ul>' => false,
      '<ul class="pagination"><li><a href="/a">Siguiente parada: la estación</a></li></ul>' => false,
      '<ul class="pagination"><li><a href="/a">次へ進むための方法</a></li></ul>' => false,
      '<ul class="pagination"><li><a href="/a">Premier</a></li></ul>' => false,
      '<ul class="pagination"><li><a href="/a">Primero</a></li></ul>' => false,
      '<ul class="pagination"><li><a href="/a">Dernier</a></li></ul>' => false
    }.each do |markup, chrome|
      it "treats #{markup[0, 60]}... inside main as chrome: #{chrome}" do
        doc = described_class.call("<html><body><main>#{markup}</main></body></html>", vocabulary: all_scope)
        list = doc.root.find { _1.name == :main }.children.first

        expect(doc.index.ignored_chrome?(list)).to be(chrome)
      end
    end

    it 'records peripheral scope for utility landmarks that are not chrome' do # rubocop:disable RSpec/ExampleLength
      doc = described_class.call(<<~HTML, vocabulary: all_scope)
        <html><body>
          <aside><header><a id="aside_header" href="/a">A</a></header></aside>
          <div role="complementary"><a id="complementary" href="/b">B</a></div>
          <dialog open><a id="dialog" href="/c">C</a></dialog>
          <div role="main"><header><a id="role_main_header" href="/d">D</a></header>
            <nav aria-label="Latest"><a id="main_nav" href="/e">E</a></nav></div>
        </body></html>
      HTML
      scopes = doc.root.find_all(&:link?).to_h do |link|
        [link.attrs.id, [doc.index.ignored_chrome?(link), doc.index.peripheral?(link)]]
      end

      expect(scopes).to eq('aside_header' => [false, true], 'complementary' => [false, true],
                           'dialog' => [true, false], 'role_main_header' => [false, false],
                           'main_nav' => [false, true])
    end
  end

  describe '.call text order' do
    it 'keeps text between inline children in the visible text', :aggregate_failures do
      document = described_class.call('<html><body><p>Hello <b>big</b> world<script>x</script>!</p></body></html>',
                                      vocabulary: all_scope)
      para = document.root.find { _1.name == :p }

      expect(para).to have_attributes(own_text: 'Hello  world!', lead_text: 'Hello ', tails: [' world!'])
      expect(para.visible_text).to eq('Hello big world!')
    end
  end

  describe '.call text slots and paths' do
    let(:html) do
      '<html><body><p>a<b>1</b><i>2</i>c<!-- note -->d<script>x</script>e</p><p>f<b>1</b></p><p></p></body></html>'
    end
    let(:paragraphs) { described_class.call(html, vocabulary: all_scope).root.find_all { _1.name == :p } }

    it 'splits direct text across the kept children, merging runs a comment splits', :aggregate_failures do
      expect(paragraphs.first).to have_attributes(own_text: 'acde', lead_text: 'a', tails: ['', 'cde'])
      expect(paragraphs[1]).to have_attributes(own_text: 'f', lead_text: 'f', tails: [''])
      expect(paragraphs.last).to have_attributes(own_text: '', lead_text: '', tails: [])
    end

    it 'freezes every text and shares one path string per ancestry', :aggregate_failures do
      first, second = paragraphs

      expect([first.own_text, *first.tails, first.tag_path]).to all(be_frozen)
      expect(first.tails).to be_frozen
      expect(second.tag_path).to be(first.tag_path)
      expect(first.tag_path).to eq('/html/body/p')
    end

    it 'shares one frozen empty own text between nodes without text', :aggregate_failures do
      document = described_class.call('<html><body><p></p><span></span></body></html>', vocabulary: all_scope)
      empty, other = document.root.find_all { %i[p span].include?(_1.name) }

      expect(empty.own_text).to be(other.own_text).and be_frozen
      expect(empty.own_text).to eq('')
    end

    it 'gives each node its own tails, so no node mutates another', :aggregate_failures do
      first, second = paragraphs

      expect(first.tails).not_to be(second.tails)
      expect { first.tails.first << 'x' }.to raise_error(FrozenError)
      expect { first.tails << 'x' }.to raise_error(FrozenError)
      expect { second.own_text << 'x' }.to raise_error(FrozenError)
    end
  end

  describe '.call shared class names' do
    let(:html) do
      '<html><body><p class="card">a</p><p class="card">b</p><p class=" card ">c</p>' \
        '<p class="card wide">d</p></body></html>'
    end
    let(:cards) { described_class.call(html, vocabulary: all_scope).root.find_all { _1.name == :p } }

    it 'shares one frozen token list between nodes with the same class attribute', :aggregate_failures do
      first, second, spaced, wide = cards.map { _1.attrs.class_names }

      expect(second).to be(first)
      expect(first).to eq(%w[card]).and be_frozen
      expect([spaced, wide]).to eq([%w[card], %w[card wide]])
      expect(spaced).not_to be(first)
    end

    it 'keeps shared tokens immutable through every node', :aggregate_failures do
      first, second = cards

      expect { second.attrs.class_names << 'x' }.to raise_error(FrozenError)
      expect { first.attrs.class_names.first << 'x' }.to raise_error(FrozenError)
      expect(second.attrs.class_names).to eq(%w[card])
    end

    it 'shares nothing between two normalizations', :aggregate_failures do
      other = described_class.call(html, vocabulary: all_scope).root.find { _1.name == :p }

      expect(other.attrs.class_names).to eq(cards.first.attrs.class_names)
      expect(other.attrs.class_names).not_to be(cards.first.attrs.class_names)
    end
  end

  describe '.call input validation' do
    it 'rejects nil and unsupported input', :aggregate_failures do
      expect do
        described_class.call(nil, vocabulary: all_scope)
      end.to raise_error(Html2rss::SST::InvalidError, 'input is required')
      expect { described_class.call(42, vocabulary: all_scope) }
        .to raise_error(Html2rss::SST::InvalidError, 'expected String or Nokogiri::XML::Node, got Integer')
    end
  end
end
