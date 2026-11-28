# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::ArticleExtractor do
  it 'rejects a value that is not a segment' do
    expect { described_class.call(Object.new, base_url: 'https://example.com', time_zone: 'UTC', link_resolver: page_resolver) }
      .to raise_error(Html2rss::AutoSource::ArticleExtractor::InvalidError, 'segment is required')
  end

  describe 'leftover hygiene' do
    let(:extractor_time_zone) { 'UTC' }
    let(:leftover_fields) do
      lambda do |html, item_selector: 'article'|
        wrapped = html.match?(/<html/i) ? html : "<html><body>#{html}</body></html>"
        doc = Html2rss::Html::SST::Normalizer.call(wrapped, vocabulary: all_scope)
        root = item_selector.split.reduce(doc.root) do |node, tag|
          node&.find { |candidate| candidate.name == tag.to_sym }
        end
        link = root.name == :a ? root : root.find(&:link?)
        segment = Html2rss::AutoSource::Segment.build(
          root_node: root, primary_link: link, strategy: :semantic, position: 0
        )
        article = described_class.call(segment, base_url: 'https://example.com', time_zone: extractor_time_zone,
                                                link_resolver: page_resolver)
        { title: article&.title, description: article&.description, published_at: article&.published_at,
          author: article&.author,
          categories: article&.categories || [], url: article&.url }
      end
    end

    it_behaves_like 'article extractor leftover hygiene'

    context 'with text a card rule already used' do
      let(:body) { '<p>Real description here that is long enough to matter for readers.</p>' }
      let(:head) { '<h3><a href="/news/story">Tram depot reopens</a></h3>' }

      it 'keeps a date scattered over fragment lines out of the description', :aggregate_failures do
        fragments = ['November', '25', ',', '2026', '| 20:15 PM'].map { |text| "<p>#{text}</p>" }.join
        result = leftover_fields.call("<article>#{head}<div>#{fragments}</div>#{body}</article>")

        expect(result[:published_at].to_s).to start_with('2026-11-25T')
        expect(result[:description]).to eq('Real description here that is long enough to matter for readers.')
      end

      it 'feeds a byline to author, not description', :aggregate_failures do
        ['Von Anna Beispiel', 'by Anna Beispiel', '27 Nov 2026 / by Anna Beispiel'].each do |byline|
          result = leftover_fields.call("<article>#{head}<p>#{byline}</p>#{body}</article>")

          expect(result[:author]).to eq('Anna Beispiel')
          expect(result[:description]).to eq('Real description here that is long enough to matter for readers.')
        end
      end

      it 'reads published_at from the date head of a "<date> / by X" byline', :aggregate_failures do
        result = leftover_fields.call("<article>#{head}<p>27 Nov 2026 / by Anna Beispiel</p>#{body}</article>")

        expect(result[:published_at].to_s).to start_with('2026-11-27T')
        expect(result[:author]).to eq('Anna Beispiel')
      end

      it 'lets a datetime attribute decide before a byline date head' do
        time = '<time datetime="2026-01-02T00:00:00Z">2 Jan</time>'
        result = leftover_fields.call("<article>#{head}#{time}<p>27 Nov 2026 / by Anna Beispiel</p>#{body}</article>")

        expect(result[:published_at].to_s).to start_with('2026-01-02T')
      end

      it 'keeps prose that starts with "By" in the description', :aggregate_failures do
        result = leftover_fields.call("<article>#{head}<p>By the end of the year the depot reopens.</p></article>")

        expect(result[:author]).to be_nil
        expect(result[:description]).to eq('By the end of the year the depot reopens.')
      end
    end
  end

  describe 'page language' do
    let(:html) do
      '<article><b class="kicker">独自</b><h2><a href="/news/story">政府が新しい港湾計画を発表した</a></h2></article>'
    end
    let(:scraper_class) { Html2rss::AutoSource::Scraper::SemanticHtml }
    let(:article_for) do
      lambda do |**options|
        described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                link_resolver: page_resolver, scraper: scraper_class, **options)
      end
    end

    it 'reads a Han type marker kicker as text only on a Chinese page', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      resolver = ->(vocabulary) { Html2rss::AutoSource::Scoring::LinkResolver.new('https://example.com', vocabulary:) }

      expect(article_for.call.title).to eq('政府が新しい港湾計画を発表した')
      expect(article_for.call(link_resolver: resolver.call(Html2rss::Vocabulary[:ja])).title)
        .to eq('政府が新しい港湾計画を発表した')
      expect(article_for.call(link_resolver: resolver.call(Html2rss::Vocabulary['zh-Hans-CN'])).title)
        .to eq('独自: 政府が新しい港湾計画を発表した')
    end

    it 'stamps the scraper class on the article' do
      expect(article_for.call.scraper).to be(scraper_class)
    end

    describe 'with a page resolver' do
      let(:han) { Html2rss::Vocabulary['zh-Hans-CN'] }
      let(:resolver) { Html2rss::AutoSource::Scoring::LinkResolver.new('https://example.com', vocabulary: han) }

      before { allow(Html2rss::AutoSource::LinkDestination::TextClassifier).to receive(:for).and_call_original }

      it "takes the resolver's vocabulary and classifier", :aggregate_failures do
        expect(article_for.call(link_resolver: resolver).title).to eq('独自: 政府が新しい港湾計画を発表した')
        expect(Html2rss::AutoSource::LinkDestination::TextClassifier).not_to have_received(:for)
      end
    end
  end

  describe 'in-heading kickers' do
    let(:title_for) do
      lambda do |html|
        described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                link_resolver: page_resolver)&.title
      end
    end

    it 'takes the single title-classed child of a multi-span heading and drops a type-marker kicker before it' do
      html = File.read(File.expand_path('../../../fixtures/auto_source/teaser_card_kicker_heading.html', __dir__))

      expect(title_for.call(html)).to eq('Evening bulletin 15:00')
    end

    it 'keeps the full text of a single-span heading' do
      html = '<article><h2><a href="/news/story"><span class="Teaser_title">Story Title</span></a></h2></article>'

      expect(title_for.call(html)).to eq('Story Title')
    end

    it 'keeps the full text of a heading with inline emphasis' do
      html = '<article><h2><a href="/news/story">Story <em>Title</em> here</a></h2></article>'

      expect(title_for.call(html)).to eq('Story Title here')
    end

    it 'keeps the full text when the heading mixes plain text with a title-classed child' do
      html = '<article><h2>Plain <span class="title">Story Title</span><span>tail</span></h2>' \
             '<a href="/news/story">Read</a></article>'

      expect(title_for.call(html)).to eq('Plain Story Title tail')
    end

    it 'keeps the full text when several children carry a title class' do
      html = '<article><h2><span class="title">One</span><span class="title">Two</span></h2>' \
             '<a href="/news/story">Read</a></article>'

      expect(title_for.call(html)).to eq('One Two')
    end

    it 'drops a subtitle piece beside the headline piece' do
      html = '<article><h2><span class="headline">Main headline here</span>' \
             '<span class="subtitle">Longer subtitle text</span></h2>' \
             '<a href="/news/story">Read</a></article>'

      expect(title_for.call(html)).to eq('Main headline here')
    end

    it 'drops a hyphen- or underscore-delimited sub-title piece beside the headline piece',
       :aggregate_failures do
      %w[sub-title sub_title Sub-Title].each do |klass|
        html = "<article><h2><span class=\"headline\">Main headline here</span><span class=\"#{klass}\">Longer " \
               'subtitle text</span></h2><a href="/news/story">Read</a></article>'

        expect(title_for.call(html)).to eq('Main headline here')
      end
    end

    it 'composes a pre-title kicker with a headline that has no title class' do
      html = '<article><h2><span class="pre-title">Weekend kicker text</span>' \
             '<span class="headline">Main headline here</span></h2>' \
             '<a href="/news/story">Read</a></article>'

      expect(title_for.call(html)).to eq('Weekend kicker text: Main headline here')
    end

    it 'composes a pre-title kicker with the title child it precedes' do
      html = '<article><h2><span class="pre-title">Weekend kicker text</span>' \
             '<span class="title">Main headline here</span></h2>' \
             '<a href="/news/story">Read</a></article>'

      expect(title_for.call(html)).to eq('Weekend kicker text: Main headline here')
    end

    it 'composes a kicker nested in the anchor when the card has no heading' do
      html = '<article><a href="/news/story"><span class="kicker">Update</span> Ferry route returns</a></article>'

      expect(title_for.call(html)).to eq('Update: Ferry route returns')
    end

    it 'keeps the full text when the only emphasised child carries a font-weight class' do
      html = '<article><h2><span class="font-bold">Live blog update:</span> <span>Rest of headline</span></h2>' \
             '<a href="/news/story">Read</a></article>'

      expect(title_for.call(html)).to eq('Live blog update: Rest of headline')
    end

    it 'takes a hyphen- or underscore-delimited title token', :aggregate_failures do
      %w[card-title Teaser_title__Ye3Ku title title-lg Card-Title].each do |klass|
        html = "<article><h2><span class=\"kicker\">K</span><span class=\"#{klass}\">Real Title</span></h2>" \
               '<a href="/news/story">Read</a></article>'

        expect(title_for.call(html)).to eq('K: Real Title')
      end
    end
  end

  describe 'card kicker prefix' do
    let(:title_for) do
      lambda do |html|
        described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                link_resolver: page_resolver)&.title
      end
    end

    it_behaves_like 'article extractor title pieces'

    describe 'a card whose kicker is found by walking the tree' do
      let(:card) do
        '<article><h2><span class="box"><span class="premium">Plus</span>' \
          '<span class="box__head">Transit</span></span> ' \
          '<span class="title"><a href="/news/story">Tram line extends</a></span></h2></article>'
      end

      it 'keeps the kicker prefix after a GC while the example holds the document' do
        segment = segment_for(card)
        GC.start

        expect(described_class.call(segment, base_url: 'https://example.com',
                                             link_resolver: page_resolver,
                                             time_zone: 'UTC').title).to eq('Transit: Tram line extends')
      end

      it 'raises rather than dropping the kicker prefix once the document is collected' do
        segment = build_orphan_segment(card)
        3.times { GC.start }

        expect { described_class.call(segment, base_url: 'https://example.com', time_zone: 'UTC', link_resolver: page_resolver) }
          .to raise_error(Html2rss::Html::SST::Index::InvalidError)
      end
    end

    it 'keeps only the topic of a kicker that also holds a clock, a time element and a field label' do
      html = '<article><header><div class="overline"><span class="date">11:46</span><i></i>' \
             '<time datetime="2026-10-20">Oct 20</time><span class="sr-only">Section:</span>' \
             '<span class="topic">Harbor</span></div>' \
             '<h2><a href="/news/story">Ferry route returns</a></h2></header></article>'

      expect(title_for.call(html)).to eq('Harbor: Ferry route returns')
    end

    it 'adds no prefix when the kicker holds only a clock' do
      html = '<article><span class="kicker"><span>09:05</span></span><h2><a href="/news/story">Story</a></h2></article>'

      expect(title_for.call(html)).to eq('Story')
    end

    it 'keeps a plain kicker as the title prefix' do
      html = '<article><span class="eyebrow">Weather</span><h2><a href="/news/story">Storm ahead</a></h2></article>'

      expect(title_for.call(html)).to eq('Weather: Storm ahead')
    end

    it 'adds no prefix when the title already opens with the kicker' do
      html = '<article><span class="eyebrow">Storm</span><h2><a href="/news/story">Storm ahead</a></h2></article>'

      expect(title_for.call(html)).to eq('Storm ahead')
    end

    it 'reads a kicker marked only by a data-tb-kicker attribute' do
      html = '<article><span data-tb-kicker="">Weather</span><h2><a href="/news/story">Storm ahead</a></h2></article>'

      expect(title_for.call(html)).to eq('Weather: Storm ahead')
    end

    it 'keeps a kicker that the title only mentions further in' do
      html = '<article><span class="eyebrow">Storm</span><h2><a href="/news/story">Big storm ahead</a></h2></article>'

      expect(title_for.call(html)).to eq('Storm: Big storm ahead')
    end

    it 'adds no prefix when the kicker wraps the heading' do
      html = '<article><div class="overline-block"><h2><a href="/news/story">Storm ahead</a></h2>' \
             '<p>Gusts reach the coast tonight.</p></div></article>'

      expect(title_for.call(html)).to eq('Storm ahead')
    end

    it 'takes no kicker from a with-kicker modifier on the card root' do
      html = '<div class="teaser teaser--with-kicker"><a href="/news/story">Tram line extends</a> ' \
             '<span>Short note on the line.</span></div>'

      expect(title_for.call(html)).to eq('Tram line extends')
    end

    it 'titles a kicker-only card with the kicker alone' do
      html = '<article><span class="eyebrow">Weather</span><a href="/news/story"><img src="/a.jpg"></a></article>'

      expect(title_for.call(html)).to eq('Weather')
    end
  end

  describe 'url-derived id' do
    subject(:id_for) do
      lambda do |href|
        html = %(<article><h2><a href="#{href}">Story Title</a></h2><p>Useful context paragraph here.</p></article>)
        described_class.call(segment_for(html, href:), base_url: 'https://example.com', time_zone: 'UTC',
                                                       link_resolver: page_resolver)&.id
      end
    end

    it 'keeps the path as id on a root-path query URL (the guid already hashes the url)', :aggregate_failures do
      expect(id_for.call('/?p=123')).to eq('/')
      expect(id_for.call('/?p=124')).to eq('/')
    end

    it 'keeps the path as id on non-root URLs' do
      expect(id_for.call('/a?p=1')).to eq('/a')
    end

    it 'emits no article for an opaque link (mailto:, tel:, javascript:)', :aggregate_failures do
      expect(id_for.call('mailto:?subject=news')).to be_nil
      expect(id_for.call('mailto:a@b.c')).to be_nil
      expect(id_for.call('javascript:void(0)')).to be_nil
    end

    it 'still builds an article for a hierarchical non-web link (Cleanup drops it later)' do
      expect(id_for.call('ftp://x.com/a')).to eq('/a')
    end

    describe 'with the page resolver' do
      let(:resolver) { Html2rss::AutoSource::Scoring::LinkResolver.new('https://example.com') }
      let(:segment) do
        html = '<article><h2><a href="/a?p=1#top">Story Title</a></h2><p>Useful context paragraph here.</p></article>'
        segment_for(html, href: '/a?p=1#top')
      end

      before do
        resolver.destination_facts(segment.primary_link)
        allow(Html2rss::Url).to receive(:from_relative).and_call_original
      end

      it 'reuses its URL of the primary link instead of resolving it again', :aggregate_failures do
        article = described_class.call(segment, base_url: 'https://example.com', time_zone: 'UTC',
                                                link_resolver: resolver)

        expect(article.url.to_s).to eq('https://example.com/a?p=1')
        expect(Html2rss::Url).not_to have_received(:from_relative)
      end

      it 'emits no article when the resolver has no facts for the primary link' do
        broken = segment_for('<article><h2><a href="http://">Story Title</a></h2><p>Useful context here.</p></article>',
                             href: 'http://')

        expect(described_class.call(broken, base_url: 'https://example.com', time_zone: 'UTC',
                                            link_resolver: resolver)).to be_nil
      end
    end

    it 'emits no article when the primary link resolves to no URL' do
      expect(id_for.call('http://')).to be_nil
    end

    it 'prefers a nested DOM id over the link path' do
      html = '<article><h2 id="headline"><a href="/news/story">Story Title</a></h2><p>Useful context.</p></article>'

      expect(described_class.call(segment_for(html), base_url: 'https://example.com',
                                                     link_resolver: page_resolver,
                                                     time_zone: 'UTC').id).to eq('headline')
    end

    it 'skips an empty DOM id and falls back to the link path' do
      html = '<article id=""><h2><a href="/news/story">Story Title</a></h2><p>Useful context here.</p></article>'

      expect(described_class.call(segment_for(html), base_url: 'https://example.com',
                                                     link_resolver: page_resolver,
                                                     time_zone: 'UTC').id).to eq('/news/story')
    end
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

    article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                      link_resolver: page_resolver, scraper: Object)

    expect(article.title).to eq('Story Title')
    expect(article.id).to eq('story-1')
    expect(article.url.to_s).to eq('https://example.com/news/story')
    expect(article.description).to include('Useful context')
    expect(article.image.to_s).to include('hero.jpg')
    expect(article.published_at).to be_a(DateTime)
    expect(article.categories).to include('Launch')
    expect(article.enclosures).not_to be_empty
  end

  describe 'published_at from a date chip inside the headline link' do
    def published_for(inner)
      html = %(<article><h3><a href="/news/story">#{inner}</a></h3></article>)
      described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                              link_resolver: page_resolver)&.published_at
    end

    it 'reads a text date chip the title drops', :aggregate_failures do
      expect(published_for('<span>Tram depot reopens</span><span class="date">12 November 2026</span>').to_s)
        .to start_with('2026-11-12T00:00:00')
      expect(published_for('<span>Tram depot reopens</span><span class="date">12 November</span>')).to be_nil
    end

    it 'reads a text date chip beside the headline link inside the heading' do
      html = %(<article><h3><a href="/news/story">Tram depot reopens</a> ) +
             %(<span class="date">12 November 2026</span></h3></article>)
      article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                        link_resolver: page_resolver)
      expect(article.published_at.to_s).to start_with('2026-11-12T00:00:00')
    end

    it 'reads a text date chip inside a card link with no heading' do
      html = %(<article><a href="/news/story"><span>Tram depot reopens</span>) +
             %(<span class="date">12 November 2026</span></a></article>)
      article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                        link_resolver: page_resolver)
      expect(article.published_at.to_s).to start_with('2026-11-12T00:00:00')
    end

    it 'keeps the exact instant of a time element wrapping the chip' do
      time = '<time datetime="2026-11-12T14:30:00Z">12 November 2026</time>'
      html = %(<article><h3><a href="/news/story"><span>Tram depot reopens</span>#{time}</a></h3></article>)
      article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'Europe/Berlin',
                                                        link_resolver: page_resolver)
      expect(article.published_at.to_s).to eq('2026-11-12T14:30:00+00:00')
    end

    it 'reads a text date chip in the channel time zone' do
      html = %(<article><a href="/news/story"><span>Tram depot reopens</span>) +
             %(<span class="date">12 November 2026</span></a></article>)
      article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'Europe/Berlin',
                                                        link_resolver: page_resolver)
      expect(article.published_at.to_s).to eq('2026-11-12T00:00:00+01:00')
    end

    it 'reads the lead paragraph inside a card anchor as the description', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = '<article><a href="/news/story"><span class="teaser__title">Tram depot reopens</span>' \
             '<p>Crews finished early.<time datetime="2026-11-12T07:25">07:25</time></p></a></article>'
      article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                        link_resolver: page_resolver)
      expect(article.title).to eq('Tram depot reopens')
      expect(article.description).to eq('Crews finished early.')
    end

    it 'leaves the paragraphs the title is built from out of the description' do
      html = '<article><a href="/news/story"><p>Tram depot reopens</p><p>Crews finished early.</p></a></article>'
      article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                        link_resolver: page_resolver)
      expect(article.description).to be_nil
    end

    it 'keeps the paragraph beside a heading title inside the anchor' do
      html = '<article><a href="/news/story"><h3>Tram depot reopens</h3><p>Crews finished early.</p></a></article>'
      article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                        link_resolver: page_resolver)
      expect(article.description).to eq('Crews finished early.')
    end

    it 'leaves a kicker paragraph the title reads out of the description' do
      html = '<article><a href="/news/story"><p>Politics</p><span>Tram depot reopens</span>' \
             '<p>Crews finished early.</p></a></article>'
      article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                        link_resolver: page_resolver)
      expect(article.description).to be_nil
    end

    it 'invents no date from a bare clock chip' do
      expect(published_for('<span class="stamp">19:47</span><span>Coalition holds special sessions</span>')).to be_nil
    end
  end

  it 'accepts a RankedSegment' do # rubocop:disable RSpec/ExampleLength
    html = '<div><h3><a href="/news/card">Linked card text here</a></h3><p>More words.</p></div>'
    doc = Html2rss::Html::SST::Normalizer.call(html, vocabulary: all_scope)
    root = doc.root.find { |n| n.name == :div }
    segment = Html2rss::AutoSource::Segment.build(root_node: root, primary_link: root.find(&:link?), strategy: :cluster,
                                                  position: 0)
    ranked = Html2rss::AutoSource::Scoring::RankedSegment.new(
      segment:,
      score: Html2rss::AutoSource::Scoring::Score.new(
        composite: 1.0,
        quality: 1.0,
        junk: 0.0,
        breakdown: Html2rss::AutoSource::Scoring::Score::EMPTY_BREAKDOWN
      )
    )

    expect(described_class.call(ranked, base_url: 'https://example.com',
                                        link_resolver: page_resolver,
                                        time_zone: 'UTC')&.title).to eq('Linked card text here')
  end

  it 'emits no article for a card without a primary link (no page#fragment URL)' do
    html = '<div id="notice"><h3>Water main maintenance</h3><p>Crews work overnight.</p></div>'
    root = Html2rss::Html::SST::Normalizer.call(html, vocabulary: all_scope).root.find { |n| n.name == :div }
    segment = Html2rss::AutoSource::Segment.build(root_node: root, primary_link: nil, strategy: :cluster, position: 0)

    expect(described_class.call(segment, base_url: 'https://example.com', time_zone: 'UTC',
                                         link_resolver: page_resolver)).to be_nil
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

    article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                      link_resolver: page_resolver)

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

    article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                      link_resolver: page_resolver)

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

    article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                      link_resolver: page_resolver)

    expect(article.title).to eq('story-has-edit-branch')
    expect(Html2rss::AutoSource::Cleanup.junk_reason(article.title,
                                                     vocabulary: Html2rss::Vocabulary[:all])).to eq(:slug)
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

    article = described_class.call(segment_for(html), base_url: 'https://example.com', time_zone: 'UTC',
                                                      link_resolver: page_resolver)

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

    article = described_class.call(segment_for(html, href: '/news/style'), base_url: 'https://example.com',
                                                                           link_resolver: page_resolver,
                                                                           time_zone: 'UTC')

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

    article = described_class.call(segment_for(html, href: '/news/media'), base_url: 'https://example.com',
                                                                           link_resolver: page_resolver,
                                                                           time_zone: 'UTC')
    zip = article.enclosures.find { |enclosure| enclosure.type == 'application/zip' }

    expect(zip).not_to be_nil
    expect(zip.url.to_s).to eq('https://example.com/downloads/bundle.zip')
  end

  it 'never turns an iframe on an SST segment into an enclosure', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    html = '<article><h2><a href="/news/embed">Embed Story</a></h2>' \
           '<p>Useful context paragraph with enough words.</p><iframe src="/embeds/player.html"></iframe></article>'

    article = described_class.call(segment_for(html, href: '/news/embed'), base_url: 'https://example.com',
                                                                           link_resolver: page_resolver,
                                                                           time_zone: 'UTC')

    expect(article.enclosures).to be_empty
  end

  it 'extracts player files in document order and the video poster as the image', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    html = <<~HTML
      <html><body>
        <article>
          <h2><a href="/news/clip">Clip Story</a></h2>
          <p>Useful context paragraph with enough words for description extraction.</p>
          <picture><source src="/images/hero.webp" type="image/webp"></picture>
          <video src="/videos/clip.mp4" poster="/posters/clip.jpg"></video>
          <audio><source src="/audio/clip.ogg" type="audio/ogg; codecs=vorbis"></audio>
        </article>
      </body></html>
    HTML

    article = described_class.call(segment_for(html, href: '/news/clip'), base_url: 'https://example.com',
                                                                          link_resolver: page_resolver,
                                                                          time_zone: 'UTC')

    expect(article.enclosures.map { [_1.url.to_s, _1.type] }).to eq(
      [%w[https://example.com/videos/clip.mp4 video/mp4],
       ['https://example.com/audio/clip.ogg', 'audio/ogg; codecs=vorbis']]
    )
    expect(article.image.to_s).to eq('https://example.com/posters/clip.jpg')
  end

  it 'types untyped player files by their nearest player, once per URL, web URLs only' do # rubocop:disable RSpec/ExampleLength
    html = <<~HTML
      <html><body>
        <article>
          <h2><a href="/news/clip">Clip Story</a></h2>
          <p>Useful context paragraph with enough words for description extraction.</p>
          <video src="/stream/clip"><source src="/stream/clip" type="video/webm"></video>
          <video><audio><source src="/stream/episode"></audio></video>
          <audio src="javascript:void(0)"></audio>
          <video src="blob:https://example.com/x"></video>
        </article>
      </body></html>
    HTML

    article = described_class.call(segment_for(html, href: '/news/clip'), base_url: 'https://example.com',
                                                                          link_resolver: page_resolver,
                                                                          time_zone: 'UTC')

    expect(article.enclosures.map { [_1.url.to_s, _1.type] }).to eq(
      [%w[https://example.com/stream/clip video/webm], %w[https://example.com/stream/episode audio/mpeg]]
    )
  end

  it 'skips inline data posters and prefers a card image over a poster', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    card = lambda do |extra|
      html = <<~HTML
        <html><body><article>
          <h2><a href="/news/clip">Clip Story</a></h2>
          <p>Useful context paragraph with enough words for description extraction.</p>
          <div poster="/posters/decoy.jpg"></div>
          <video src="/videos/clip.mp4"></video>
          <video poster="data:image/png;base64,AAAA"></video>
          <video poster="/posters/clip.jpg"></video>
          <video poster="/posters/later.jpg"></video>
          #{extra}
        </article></body></html>
      HTML
      described_class.call(segment_for(html, href: '/news/clip'), base_url: 'https://example.com',
                                                                  link_resolver: page_resolver,
                                                                  time_zone: 'UTC').image.to_s
    end

    expect(card.call('')).to eq('https://example.com/posters/clip.jpg')
    expect(card.call('<img src="/images/photo.jpg" alt="">')).to eq('https://example.com/images/photo.jpg')
    expect(card.call('<img src="/images/photo.jpg" srcset="/images/wide.jpg 800w" alt="">'))
      .to eq('https://example.com/images/wide.jpg')
    expect(card.call('<a href="/files/report.pdf" srcset="/files/report.pdf 800w">Report</a>'))
      .to eq('https://example.com/posters/clip.jpg')
  end

  it 'gives a card without any image no image' do # rubocop:disable RSpec/ExampleLength
    html = <<~HTML
      <html><body><article>
        <h2><a href="/news/clip">Clip Story</a></h2>
        <p>Useful context paragraph with enough words for description extraction.</p>
        <video src="/videos/clip.mp4"></video>
      </article></body></html>
    HTML

    expect(described_class.call(segment_for(html, href: '/news/clip'), base_url: 'https://example.com',
                                                                       link_resolver: page_resolver,
                                                                       time_zone: 'UTC').image).to be_nil
  end
end
