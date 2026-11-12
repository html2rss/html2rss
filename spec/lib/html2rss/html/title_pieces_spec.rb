# frozen_string_literal: true

RSpec.describe Html2rss::Html::TitlePieces do
  context 'with Nokogiri nodes' do
    let(:pieces_for) do
      lambda do |html|
        root = Nokogiri::HTML.fragment(html).at_css('article')
        anchor = root.at_css('a[href]')
        source = root.at_css('h1, h2, h3, h4, h5, h6') || anchor
        [described_class.new(root, source, anchor:), root, source]
      end
    end
    let(:title_for) do
      lambda do |html|
        pieces, _, source = pieces_for.call(html)
        Html2rss::Article::Title.compose(pieces.headline_text(source), kicker: pieces.kicker_text)
      end
    end

    it_behaves_like 'article extractor title pieces'

    it 'reads no headline from a heading holding only a date chip inside a time element' do
      pieces, _, source = pieces_for.call(%(<article><h3><time datetime="2026-11-12"><span>11月12日</span></time></h3>) +
                                          %(<a href="/s">Tram line extends</a></article>))
      expect(pieces.headline_text(source)).to be_nil
    end

    it 'returns the kicker element and memoizes a missing one', :aggregate_failures do
      pieces, root, = pieces_for.call('<article><b class="kicker">Transit</b><h2><a href="/s">Tram</a></h2></article>')
      expect(pieces.kicker).to equal(root.at_css('b'))

      bare, = pieces_for.call('<article><h2><a href="/s">Tram</a></h2></article>')
      expect([bare.kicker, bare.kicker, bare.kicker_text]).to eq([nil, nil, nil])
    end

    it 'takes a data-tb-kicker element as the kicker' do
      pieces, = pieces_for.call('<article><b data-tb-kicker="">Transit</b><h2><a href="/s">Tram</a></h2></article>')
      expect(pieces.kicker_text).to eq('Transit')
    end

    it 'takes a marked element as the kicker when the card has no headline source' do
      root = Nokogiri::HTML.fragment('<article><b class="kicker">Transit</b><p>Tram</p></article>').at_css('article')
      expect(described_class.new(root, nil).kicker_text).to eq('Transit')
    end

    it 'finds no kicker without a marked one or a headline source' do
      root = Nokogiri::HTML.fragment('<article><b>Transit</b><p>Tram</p></article>').at_css('article')
      expect(described_class.new(root, nil).kicker).to be_nil
    end

    it 'reads a heading whose only link is not the selected anchor as a whole' do
      html = '<article><a href="/s">Pics</a><h2><span>Transit</span> <a href="/t">Tram line extends</a></h2></article>'
      expect(title_for.call(html)).to eq('Transit Tram line extends')
    end

    it 'returns nil headline text without a node' do
      pieces, = pieces_for.call('<article><h2><a href="/s">Tram</a></h2></article>')
      expect(pieces.headline_text(nil)).to be_nil
    end

    it 'drops every noise element opening the headline, then keeps the rest' do
      html = '<article><h2><a href="/s"><time>19:47</time> <i>Section:</i> Tram at <b>20:15</b></a></h2></article>'
      expect(title_for.call(html)).to eq('Tram at 20:15')
    end
  end

  context 'with SST nodes' do
    let(:pieces_for) do
      lambda do |html|
        doc = Html2rss::SST::Normalizer.call("<html><body>#{html}</body></html>")
        root = doc.root.find { _1.name == :article }
        anchor = root.find(&:link?)
        source = root.find(&:heading?) || anchor
        [described_class.new(root, source, anchor:), root, source]
      end
    end
    let(:title_for) do
      lambda do |html|
        pieces, _, source = pieces_for.call(html)
        Html2rss::Article::Title.compose(pieces.headline_text(source), kicker: pieces.kicker_text)
      end
    end

    it_behaves_like 'article extractor title pieces'

    it 'reads no headline from a heading holding only a date chip inside a time element' do
      pieces, _, source = pieces_for.call(%(<article><h3><time datetime="2026-11-12"><span>11月12日</span></time></h3>) +
                                          %(<a href="/s">Tram line extends</a></article>))
      expect(pieces.headline_text(source)).to be_nil
    end

    it 'takes a data-tb-kicker element as the kicker' do
      pieces, = pieces_for.call('<article><b data-tb-kicker="">Transit</b><h2><a href="/s">Tram</a></h2></article>')
      expect(pieces.kicker_text).to eq('Transit')
    end

    it 'reads a heading whose only link is not the selected anchor as a whole' do
      html = '<article><a href="/s">Pics</a><h2><span>Transit</span> <a href="/t">Tram line extends</a></h2></article>'
      expect(title_for.call(html)).to eq('Transit Tram line extends')
    end

    context 'with unindexed nodes' do
      let(:kicker) do
        Html2rss::SST::Node.build(name: :span, attrs: Html2rss::SST::Attrs.build(class_names: ['kicker']),
                                  own_text: 'Transit')
      end
      let(:heading) do
        anchor = Html2rss::SST::Node.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '/s'), own_text: 'Tram')
        Html2rss::SST::Node.build(name: :h2, children: [kicker, anchor])
      end
      let(:pieces) { described_class.new(Html2rss::SST::Node.build(name: :article, children: [heading]), heading) }

      it 'judges them by walking the tree', :aggregate_failures do
        expect(pieces.kicker).to equal(kicker)
        expect(pieces.headline_text(heading)).to eq('Tram')
      end

      it 'finds no piece before a title piece without parents' do
        title = kicker.with(attrs: kicker.attrs.with(class_names: ['title']), own_text: 'Tram')
        box = heading.with(children: [kicker.with(attrs: Html2rss::SST::Attrs.build), title])
        bare = described_class.new(Html2rss::SST::Node.build(name: :article, children: [box]), box)

        expect([bare.kicker, bare.headline_text(box)]).to eq([nil, 'Tram'])
      end

      it 'drops a time element without a parent to read running text from' do
        time = Html2rss::SST::Node.build(name: :time, own_text: 'Friday')
        expect(pieces.headline_text(heading.with(children: [time, *heading.children]))).to eq('Tram')
      end
    end
  end
end
