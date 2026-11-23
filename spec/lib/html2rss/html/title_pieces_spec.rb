# frozen_string_literal: true

RSpec.describe Html2rss::Html::TitlePieces do
  context 'with SST nodes' do
    let(:pieces_for) do
      lambda do |html|
        doc = Html2rss::SST::Normalizer.call("<html><body>#{html}</body></html>", vocabulary: all_scope)
        root = doc.root.find { _1.name == :article }
        anchor = root.find(&:link?)
        source = root.find(&:heading?) || anchor
        [described_class.new(root, source, anchor:, vocabulary: all_scope), root, source]
      end
    end
    let(:title_for) do
      lambda do |html|
        pieces, _, source = pieces_for.call(html)
        Html2rss::Article::Title.compose(pieces.headline_text(source), kicker: pieces.kicker_text,
                                                                       vocabulary: all_scope)
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

    it 'returns the kicker element and memoizes a missing one', :aggregate_failures do
      pieces, root, = pieces_for.call('<article><b class="kicker">Transit</b><h2><a href="/s">Tram</a></h2></article>')
      expect(pieces.kicker).to equal(root.find { _1.name == :b })

      bare, = pieces_for.call('<article><h2><a href="/s">Tram</a></h2></article>')
      expect([bare.kicker, bare.kicker, bare.kicker_text]).to eq([nil, nil, nil])
    end

    it 'drops a Han type marker piece from the kicker unless the page is Chinese' do
      _, root, = pieces_for.call('<article><b class="kicker"><i>独自</i> Transit</b><h2>T</h2></article>')
      heading = root.find(&:heading?)
      kicker_text = ->(vocabulary) { described_class.new(root, heading, vocabulary:).kicker_text }

      expect([Html2rss::Vocabulary[:ja], Html2rss::Vocabulary['zh-Hant']].map(&kicker_text))
        .to eq(['Transit', '独自 Transit'])
    end

    it 'takes a marked element as the kicker when the card has no headline source' do
      _, root, = pieces_for.call('<article><b class="kicker">Transit</b><p>Tram</p></article>')
      expect(described_class.new(root, nil, vocabulary: all_scope).kicker_text).to eq('Transit')
    end

    it 'finds no kicker without a marked one or a headline source' do
      _, root, = pieces_for.call('<article><b>Transit</b><p>Tram</p></article>')
      expect(described_class.new(root, nil, vocabulary: all_scope).kicker).to be_nil
    end

    it 'returns nil headline text without a node' do
      pieces, = pieces_for.call('<article><h2><a href="/s">Tram</a></h2></article>')
      expect(pieces.headline_text(nil)).to be_nil
    end

    it 'drops every noise element opening the headline, then keeps the rest' do
      html = '<article><h2><a href="/s"><time>19:47</time> <i>Section:</i> Tram at <b>20:15</b></a></h2></article>'
      expect(title_for.call(html)).to eq('Tram at 20:15')
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
      let(:pieces) { described_class.new(Html2rss::SST::Node.build(name: :article, children: [heading]), heading, vocabulary: all_scope) }

      it 'judges them by walking the tree', :aggregate_failures do
        expect(pieces.kicker).to equal(kicker)
        expect(pieces.headline_text(heading)).to eq('Tram')
      end

      it 'finds no piece before a title piece without parents' do
        title = kicker.with(attrs: kicker.attrs.with(class_names: ['title']), own_text: 'Tram')
        box = heading.with(children: [kicker.with(attrs: Html2rss::SST::Attrs.build), title])
        bare = described_class.new(Html2rss::SST::Node.build(name: :article, children: [box]), box,
                                   vocabulary: all_scope)

        expect([bare.kicker, bare.headline_text(box)]).to eq([nil, 'Tram'])
      end

      it 'drops a time element without a parent to read running text from' do
        time = Html2rss::SST::Node.build(name: :time, own_text: 'Friday')
        expect(pieces.headline_text(heading.with(children: [time, *heading.children]))).to eq('Tram')
      end
    end
  end

  context 'with a page-only language declaring the date and label concepts' do
    let(:xx) do
      terms = Html2rss::Vocabulary::CONCEPTS.to_h { [_1, Html2rss::Vocabulary::NONE] }
      terms[:type_label] = %w[soort-xx]
      terms[:paid_label] = %w[betaald-xx]
      terms[:date_piece] = [/\d{1,2}-mnd-xx/]
      language = Html2rss::Vocabulary::Language.new(code: :xx, terms: terms.freeze)
      Html2rss::Vocabulary.build_scope(:zh, Html2rss::Vocabulary::SHARED_LANGUAGES, own: [language])
    end
    let(:headline) do
      lambda do |html, vocabulary|
        doc = Html2rss::SST::Normalizer.call("<html><body>#{html}</body></html>", vocabulary:)
        root = doc.root.find { _1.name == :article }
        heading = root.find { _1.name == :h2 }
        [described_class.new(root, heading, anchor: root.find(&:link?), vocabulary:).headline_text(heading), doc].first
      end
    end

    before do
      own = Html2rss::Article::Title::OWN_CONCEPTS.to_h { [_1, xx.own_alternation(_1)] }
      rules = Html2rss::Article::Title::Rules.build(xx.type_markers, own)
      table = Html2rss::Article::Title.const_get(:RULES_BY_SCOPE).merge(zh: rules)
      stub_const('Html2rss::Article::Title::RULES_BY_SCOPE', table)
      label_text = Html2rss::LinkDestination::Sponsorship::LabelText
      paid = label_text.build(%i[paid_label ad_word element_label].to_h { [_1, xx.own_alternation(_1)] })
      stub_const("#{label_text}::BY_SCOPE", label_text.const_get(:BY_SCOPE).merge(zh: paid))
    end

    it 'keeps an own date term that stands inside running text', :aggregate_failures do
      inline = '<article><h2><a href="/s">Haven opent <time>12-mnd-xx</time></a></h2></article>'
      plain = '<article><h2><a href="/s">Haven opent <span>12-mnd-xx</span></a></h2></article>'

      expect(headline.call(inline, xx)).to eq('Haven opent 12-mnd-xx')
      expect(headline.call(plain, xx)).to eq('Haven opent 12-mnd-xx')
    end

    it 'drops an own label before the headline words' do
      labelled = '<article><h2><a href="/s"><span>Soort-xx:</span> Haven opent kade</a></h2></article>'

      expect(headline.call(labelled, xx)).to eq('Haven opent kade')
    end

    it 'keeps an own label when only a clock or a bar would be left', :aggregate_failures do
      ['<span>Betaald-xx</span> 12:30 14:15 16:40', '<span>Betaald-xx</span> 12:30',
       '<span>Betaald-xx</span>｜<span>12:30</span>'].each do |inner|
        html = %(<article><h2>#{inner}</h2><a href="/s">x</a></article>)

        expect(headline.call(html, xx)).to match(/Betaald-xx/i), inner
      end
    end

    it 'keeps an own label that would leave the headline below the title floor', :aggregate_failures do
      short = '<article><h2><span>Soort-xx:</span> Haven opent</h2><a href="/s">x</a></article>'
      long = '<article><h2><span>Soort-xx:</span> Haven opent nieuwe kade</h2><a href="/s">x</a></article>'

      expect(headline.call(short, xx)).to eq('Soort-xx: Haven opent')
      expect(headline.call(long, xx)).to eq('Haven opent nieuwe kade')
    end

    it 'reads no own term in a shared scope', :aggregate_failures do
      html = '<article><h2><span>Soort-xx:</span> Haven opent</h2><a href="/s">x</a></article>'

      expect(headline.call(html, all_scope)).to eq('Soort-xx: Haven opent')
      expect(xx.own?).to be(true)
      expect(all_scope.own?).to be(false)
    end

    it 'keeps a headline that own terms alone would empty, whatever the drops', # rubocop:disable RSpec/ExampleLength
       :aggregate_failures do
      [
        '<span>Soort-xx:</span>', '<span>Betaald-xx</span>',
        '<span>Soort-xx:</span><span>12:30</span>', '<span>Betaald-xx</span><span>12:30</span>',
        '<span>Betaald-xx</span> <span>12:30</span>', '<time>12-mnd-xx</time>',
        '<a href="/s"><time>12-mnd-xx</time></a>'
      ].flat_map { |inner| [%(<a href="/s">#{inner}</a>), inner] }.each do |inner|
        html = %(<article><h2>#{inner}</h2><a href="/s">x</a></article>)

        expect(headline.call(html, xx)).not_to be_nil, inner
      end
    end
  end
end
