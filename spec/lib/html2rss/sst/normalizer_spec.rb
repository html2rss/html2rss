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

    it 'does not copy typed attributes into the raw hash' do
      link = described_class.call('<html><body><a href="/x" id="y">q</a></body></html>').root
                            .find { |n| n.name == :a }

      expect(link.attrs.raw).to eq({})
    end

    it 'logs which root fallback was used', :aggregate_failures do
      allow(Html2rss::Log).to receive(:warn)

      described_class.call(Nokogiri::XML('<root><body><p>x</p></body></root>'))
      expect(Html2rss::Log).to have_received(:warn).with(a_string_including('"reason":"body"'))

      described_class.call(Nokogiri::XML('<root><div>x</div></root>'))
      expect(Html2rss::Log).to have_received(:warn).with(a_string_including('"reason":"first_element_child"'))
    end

    it 'returns nil when the parsed input has no element to root the tree', :aggregate_failures do
      allow(Html2rss::Log).to receive(:warn)

      expect(described_class.call(Nokogiri::XML('<!-- c -->'))).to be_nil
      expect(Html2rss::Log).to have_received(:warn).with(a_string_including('"reason":"self"'))
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
      expect { described_class.call(nil) }.to raise_error(Html2rss::InvalidOption, 'input is required')
      expect { described_class.call(42) }
        .to raise_error(Html2rss::InvalidOption, 'expected String or Nokogiri::XML::Node, got Integer')
    end
  end
end
