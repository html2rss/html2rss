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
      doc = described_class.call(simple_html)
      expect(doc.root.find { |n| n.name == :script }).to be_nil
    end

    it 'keeps a noscript only as the file links inside it, as chrome with invisible text', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      doc = described_class.call('<html><body><article><h2>Episode</h2><noscript><p>Listen <a href="/a.mp3">Get</a>' \
                                 '<a href="/page">Page</a><img src="/i.jpg"></p></noscript></article></body></html>')
      noscript = doc.root.find { |n| n.name == :noscript }

      expect(noscript.children.map { [_1.name, _1.attrs.href] }).to eq([[:a, '/a.mp3']])
      expect(doc.index.ignored_chrome?(noscript.children.first)).to be(true)
      expect(Html2rss::SST::Text.extract(doc.index.parent_of(noscript))).to eq('Episode')
    end

    it 'strips other hidden containers even when they hold file links' do
      doc = described_class.call('<html><body><p>x</p><template><a href="/t.mp3">T</a></template>' \
                                 '<svg><a href="/s.mp3">S</a></svg></body></html>')

      expect(doc.root.find_all { |n| n.name != :html && n.name != :body && n.name != :p }).to be_empty
    end

    it 'strips a noscript without file links', :aggregate_failures do
      doc = described_class.call('<html><body><p>x</p><noscript><a href="/page">Page</a><img src="/i.jpg">' \
                                 '</noscript></body></html>')

      expect(doc.root.find { |n| n.name == :noscript }).to be_nil
      expect(doc.node_count).to eq(3)
    end

    it 'builds typed Attrs on nodes', :aggregate_failures do
      doc = described_class.call(simple_html)
      article = doc.root.find { |n| n.name == :article }

      expect(article.attrs).to be_a(Html2rss::SST::Attrs)
      expect(article.attrs.class_names).to include('card', 'teaser')
    end

    it 'maps typed attributes and keeps only allowlisted raw attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = '<html><body><div id="i" class=" a  b " datetime="2020" itemprop="x" style="c:d" srcset="s 1x" ' \
             'type="t" data-k="v" aria-label="L" role="r" width="3" onclick="x">q</div></body></html>'
      div = described_class.call(html).root.find { |n| n.name == :div }

      expect(div.attrs.to_h).to eq(
        href: nil, src: nil, id: 'i', class_names: %w[a b], datetime: '2020', itemprop: 'x', style: 'c:d',
        srcset: 's 1x', type: 't', raw: { 'data-k' => 'v', 'aria-label' => 'L', 'role' => 'r' }
      )
    end

    it 'keeps hidden and aria-hidden for sponsorship markers but no attribute that only starts with hidden' do
      html = '<html><body><span class="ad-label" hidden aria-hidden="true" hiddenx="1">q</span></body></html>'
      span = described_class.call(html).root.find { |n| n.name == :span }

      expect(span.attrs.raw).to eq('hidden' => '', 'aria-hidden' => 'true')
    end

    it 'keeps rel for sponsorship markers but no attribute that only starts with rel' do
      html = '<html><body><a href="/x" rel="sponsored nofollow" release="1">q</a></body></html>'
      link = described_class.call(html).root.find { |n| n.name == :a }

      expect(link.attrs.raw).to eq('rel' => 'sponsored nofollow')
    end

    it 'maps href and src onto typed attrs', :aggregate_failures do
      doc = described_class.call('<html><body><a href="/post">Post</a><img src="/cover.png"></body></html>')

      expect(doc.root.find { |n| n.name == :a }.attrs.href).to eq('/post')
      expect(doc.root.find { |n| n.name == :img }.attrs.src).to eq('/cover.png')
    end

    it 'does not copy typed attributes into the raw hash' do
      link = described_class.call('<html><body><a href="/x" id="y">q</a></body></html>').root
                            .find { |n| n.name == :a }

      expect(link.attrs.raw).to eq({})
    end

    it 'logs which root fallback was used', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(Html2rss::Log).to receive(:warn)
      fallback = lambda do |reason, message|
        { event_name: 'sst.normalizer.root_fallback', reason:, message: }.to_json
      end

      described_class.call(Nokogiri::XML('<root><body><p>x</p></body></root>'))
      expect(Html2rss::Log).to have_received(:warn)
        .with(fallback.call('body', 'sst.normalizer root fallback: body'))

      described_class.call(Nokogiri::XML('<root><div>x</div></root>'))
      expect(Html2rss::Log).to have_received(:warn)
        .with(fallback.call('first_element_child', 'sst.normalizer root fallback: first element child'))
    end

    it 'returns nil when the parsed input has no element to root the tree', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(Html2rss::Log).to receive(:warn)

      expect(described_class.call(Nokogiri::XML('<!-- c -->'))).to be_nil
      expect(Html2rss::Log).to have_received(:warn).with(
        { event_name: 'sst.normalizer.root_fallback', reason: 'self',
          message: 'sst.normalizer root fallback: self' }.to_json
      )
    end

    it 'indexes the exact parent instance even for structurally identical siblings', :aggregate_failures do
      doc = described_class.call('<html><body><div><p>x</p></div><div><p>x</p></div></body></html>')
      body = doc.root.find { |n| n.name == :body }
      first_div, second_div = body.children

      expect(doc.index.parent_of(first_div.children.first)).to equal(first_div)
      expect(doc.index.parent_of(second_div.children.first)).to equal(second_div)
    end

    it 'does not log a root fallback for a regular html document' do
      allow(Html2rss::Log).to receive(:warn)

      described_class.call('<html><body><p>x</p></body></html>')
      expect(Html2rss::Log).not_to have_received(:warn)
    end

    it 'indexes parent relationships' do
      doc = described_class.call(simple_html)
      article = doc.root.find { |n| n.name == :article }
      expect(doc.index.parent_of(article.children.first)).to eq(article)
    end

    it 'accepts an already-parsed Nokogiri node without re-wrapping' do
      node = Nokogiri::HTML(simple_html)
      expect(described_class.call(node).root.find { |n| n.name == :article }).not_to be_nil
    end

    it 'normalizes HTML fragments from the first element child', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      fragment = Nokogiri::HTML.fragment('<article><a href="/p">Post</a></article>')
      allow(Html2rss::Log).to receive(:warn)

      doc = described_class.call(fragment)

      expect(doc.root.name).to eq(:article)
      expect(doc.root.find { |n| n.name == :a }).not_to be_nil
      expect(Html2rss::Log).to have_received(:warn).with(/first element child/)
    end

    it 'normalizes script-only body nodes from the body root', :aggregate_failures do
      body = Nokogiri::HTML('<html><body><script>evil()</script></body></html>').at_css('body')
      allow(Html2rss::Log).to receive(:warn)

      doc = described_class.call(body)

      expect(doc.root.name).to eq(:body)
      expect(Html2rss::Log).to have_received(:warn).with(/root fallback: self/)
    end

    it 'degrades when MAX_NODES is breached', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      stub_const('Html2rss::SST::Normalizer::MAX_NODES', 3)
      allow(Html2rss::Log).to receive(:warn)

      html = '<html><body><div><div><div><p>x</p></div></div></div></body></html>'
      doc = described_class.call(html)

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
      doc = described_class.call('<html><body><span>x</span><p>y</p></body></html>')

      expect(doc.degraded).to be(true)
      expect(doc.root.find { |node| node.name == :span }).to be_nil
      expect(doc.root.find { |node| node.name == :p }).not_to be_nil
    end

    it 'degrades on the node that reaches the ceiling' do
      stub_const('Html2rss::SST::Normalizer::MAX_NODES', 2)
      allow(Html2rss::Log).to receive(:warn)

      doc = described_class.call('<html><body><article>x</article></body></html>')

      expect(doc.degraded).to be(true)
    end

    it 'records path, depth, chrome, text, and node count', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = '<html><body><header><a href="/home">Home</a></header><article><p>Post</p></article></body></html>'
      doc = described_class.call(html)
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
      expect(described_class.call(text)).to be_nil
    end

    %w[article section aside main].each do |section|
      it "keeps header, its link, and footer inside #{section} out of chrome" do # rubocop:disable RSpec/ExampleLength
        doc = described_class.call("<html><body><#{section}><header><a href=\"/p\">P</a></header>" \
                                   "<footer>F</footer></#{section}></body></html>")
        header = doc.root.find { _1.name == :header }
        nodes = [header, header.children.first, doc.root.find { _1.name == :footer }]
        chrome = nodes.map { doc.index.ignored_chrome?(_1) }

        expect(chrome).to eq([false, false, false])
      end
    end

    it 'keeps page-level header and footer as chrome', :aggregate_failures do
      doc = described_class.call('<html><body><header>H</header><div><footer>F</footer></div></body></html>')

      expect(doc.index.ignored_chrome?(doc.root.find { _1.name == :header })).to be(true)
      expect(doc.index.ignored_chrome?(doc.root.find { _1.name == :footer })).to be(true)
    end

    it 'keeps chrome for headers under a page-level nav or footer', :aggregate_failures do
      doc = described_class.call('<html><body><div><nav><header id="n">N</header></nav></div><footer>' \
                                 '<article><header id="f"><a href="/f">F</a></header></article></footer></body></html>')
      chrome = %w[n f].map { |id| doc.index.ignored_chrome?(doc.root.find { _1.attrs.id == id }) }

      expect(chrome).to eq([true, true])
      expect(doc.index.ignored_chrome?(doc.root.find(&:link?))).to be(true)
    end

    it 'scopes nav and ARIA roles like header/footer, keeping pagers chrome' do # rubocop:disable RSpec/ExampleLength
      doc = described_class.call(<<~HTML)
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
      '<nav class="gsc-pagination" aria-label="Select a page"><a href="/a">A</a></nav>' => true
    }.each do |markup, chrome|
      it "treats #{markup[0, 60]}... inside main as chrome: #{chrome}" do
        doc = described_class.call("<html><body><main>#{markup}</main></body></html>")
        list = doc.root.find { _1.name == :main }.children.first

        expect(doc.index.ignored_chrome?(list)).to be(chrome)
      end
    end

    it 'records peripheral scope for utility landmarks that are not chrome' do # rubocop:disable RSpec/ExampleLength
      doc = described_class.call(<<~HTML)
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
      document = described_class.call('<html><body><p>Hello <b>big</b> world<script>x</script>!</p></body></html>')
      para = document.root.find { _1.name == :p }

      expect(para).to have_attributes(own_text: 'Hello  world!', lead_text: 'Hello ', tails: [' world!'])
      expect(para.visible_text).to eq('Hello big world!')
    end
  end

  describe '.call input validation' do
    it 'rejects nil and unsupported input', :aggregate_failures do
      expect { described_class.call(nil) }.to raise_error(Html2rss::SST::InvalidError, 'input is required')
      expect { described_class.call(42) }
        .to raise_error(Html2rss::SST::InvalidError, 'expected String or Nokogiri::XML::Node, got Integer')
    end
  end

  describe 'chrome scope rule (SST::Tags.chrome_scope)' do
    {
      %w[<div> page] => :page,
      %w[<header> page] => :chrome,
      %w[<footer> page] => :chrome,
      %w[<nav> page] => :chrome,
      %w[<dialog> sectioned] => :chrome,
      %w[<nav> sectioned] => :peripheral,
      %w[<footer> sectioned] => :peripheral,
      %w[<aside> page] => :peripheral,
      %w[<menu> page] => :peripheral,
      ['<div role="complementary">', 'page'] => :peripheral,
      %w[<header> peripheral] => :peripheral,
      %w[<article> peripheral] => :peripheral,
      ['<div role="banner">', 'peripheral'] => :peripheral,
      ['<div role="navigation">', 'peripheral'] => :chrome,
      %w[<header> sectioned] => :sectioned,
      %w[<section> page] => :sectioned,
      ['<div role="main">', 'page'] => :sectioned,
      ['<div role="MAIN">', 'page'] => :sectioned,
      ['<div role="mainly">', 'page'] => :page,
      %w[<article> chrome] => :chrome,
      %w[<div> sectioned] => :sectioned,
      %w[<svg> sectioned] => :chrome
    }.each do |(markup, scope), expected|
      it "maps #{markup} under #{scope} to #{expected}" do
        element = Nokogiri::HTML::DocumentFragment.parse(markup).child

        expect(Html2rss::SST::Tags.chrome_scope(element, scope.to_sym)).to eq(expected)
      end
    end

    {
      %w[nav] => true, %w[aside] => true, %w[footer] => true, %w[menu] => true, %w[div navigation] => true,
      %w[div menubar] => true, %w[div alertdialog] => true, %w[div complementary] => true,
      %w[div search] => false, %w[div] => false
    }.each do |(tag, role), expected|
      it "judges #{tag} role=#{role.inspect} as utility landmark: #{expected}" do
        expect(Html2rss::SST::Tags.utility_landmark?(tag, role)).to be(expected)
      end
    end

    {
      %w[header] => true, %w[div Contentinfo] => true, %w[div banner] => true, %w[nav] => false, %w[div main] => false
    }.each do |(tag, role), expected|
      it "judges #{tag} role=#{role.inspect} as page-level chrome: #{expected}" do
        expect(Html2rss::SST::Tags.page_level_chrome?(tag, role)).to be(expected)
      end
    end
  end
end
