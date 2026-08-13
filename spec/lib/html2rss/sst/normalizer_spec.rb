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

    it 'indexes parent relationships' do
      doc = described_class.call(simple_html)
      article = doc.root.find { |n| n.name == :article }
      expect(doc.index.parent_of(article.children.first)).to eq(article)
    end

    it 'accepts an already-parsed Nokogiri node without re-wrapping' do
      node = Nokogiri::HTML(simple_html)
      expect(described_class.call(node).root.find { |n| n.name == :article }).not_to be_nil
    end

    it 'degrades when MAX_NODES is breached', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      stub_const('Html2rss::SST::Normalizer::MAX_NODES', 3)
      allow(Html2rss::Log).to receive(:warn)

      html = '<html><body><div><div><div><p>x</p></div></div></div></body></html>'
      doc = described_class.call(html)

      expect(doc.degraded).to be(true)
      expect(Html2rss::Log).to have_received(:warn).with(/sst\.normalizer MAX_NODES/)
    end
  end
end
