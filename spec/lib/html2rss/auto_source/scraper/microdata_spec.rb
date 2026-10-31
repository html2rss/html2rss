# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Microdata do
  subject(:scraper) { described_class.new(parsed_body, url: base_url) }

  let(:base_url) { Html2rss::Url.from_absolute('https://example.com') }

  describe '.options_key' do
    it { expect(described_class.options_key).to eq(:microdata) }
  end

  describe '.request_slots' do
    it 'reserves no request slots with or without options', :aggregate_failures do
      expect(described_class.request_slots).to eq(0)
      expect(described_class.request_slots(max_slots: 5)).to eq(0)
    end
  end

  describe '.articles?' do
    subject(:articles?) { described_class.articles?(parsed_body) }

    context 'with supported article microdata' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <h1 itemprop="headline">Microdata headline</h1>
            <a itemprop="url" href="/stories/microdata-headline">Read more</a>
          </article>
        HTML
      end

      it { is_expected.to be(true) }
    end

    context 'with lowercase itemtype URL' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/newsarticle">
            <h1 itemprop="headline">Lowercase type headline</h1>
            <a itemprop="url" href="/stories/lowercase-type">Read more</a>
          </article>
        HTML
      end

      it { is_expected.to be(true) }
    end

    context 'with supported items nested inside another item property' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <div itemscope itemtype="https://schema.org/ItemList">
            <article itemprop="itemListElement" itemscope itemtype="https://schema.org/NewsArticle">
              <h1 itemprop="headline">Nested article</h1>
              <a itemprop="url" href="/stories/nested-article">Read more</a>
            </article>
          </div>
        HTML
      end

      it { is_expected.to be(false) }
    end

    context 'with unsupported microdata types' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <div itemscope itemtype="https://schema.org/Person">
            <span itemprop="name">Jane Doe</span>
          </div>
        HTML
      end

      it { is_expected.to be(false) }
    end
  end

  describe '#each' do
    subject(:articles) { scraper.each.to_a }

    context 'with nested item ids, html ancestors, abstracts, and tags' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html itemscope itemprop="webPage">
          <body>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline">Nested page id</span>
            <div itemprop="mainEntityOfPage" itemscope itemtype="https://schema.org/WebPage" itemid="/page/nested"></div>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline">Abstract fallback</span>
            <span itemprop="abstract">Short abstract</span>
            <span itemprop="tags">Travel</span>
            <a itemprop="url" href="/abstract">Open</a>
          </article>
          </body>
          </html>
        HTML
      end

      it 'uses nested item ids as urls, keeps html-level items, and reads abstracts and tags', :aggregate_failures do
        expect(articles.map { _1[:url].to_s }).to eq(['https://example.com/page/nested', 'https://example.com/abstract'])
        expect(articles.first[:title]).to eq('Nested page id')
        expect(articles.last).to include(description: 'Short abstract', categories: ['Travel'])
      end
    end

    context 'with title-only and description-only articles' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <h1 itemprop="headline">Title only</h1>
            <a itemprop="url" href="/title-only">Open</a>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <p itemprop="description">Description only</p>
            <a itemprop="url" href="/description-only">Open</a>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <a itemprop="url" href="/neither">Open</a>
          </article>
        HTML
      end

      it 'keeps articles with either a title or a description and drops empty ones', :aggregate_failures do
        expect(articles.map { _1[:id] }).to eq(%w[/title-only /description-only])
        expect(articles.first).not_to have_key(:description)
        expect(articles.last).not_to have_key(:title)
      end
    end

    context 'with articles that have no url' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <h1 itemprop="headline">Titled but unlinked</h1>
            <p itemprop="description">Described but unlinked</p>
          </article>
        HTML
      end

      it { expect(articles).to eq([]) }
    end

    context 'with competing title properties' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <h1 itemprop="headline">Headline wins</h1><span itemprop="title">Title</span><span itemprop="name">Name</span>
            <a itemprop="url" href="/headline">Open</a>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="title">Title wins</span><span itemprop="name">Name</span>
            <a itemprop="url" href="/title">Open</a>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="name">Name only</span>
            <a itemprop="url" href="/name">Open</a>
          </article>
        HTML
      end

      it 'prefers headline, then title, then name' do
        expect(articles.map { _1[:title] }).to eq(['Headline wins', 'Title wins', 'Name only'])
      end
    end

    context 'with competing published date properties' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="datePublished">2024-01-01</span><span itemprop="dateCreated">2023-01-01</span>
            <span itemprop="dateModified">2022-01-01</span><span itemprop="uploadDate">2021-01-01</span>
            <span itemprop="headline">Published</span><a itemprop="url" href="/published">Open</a>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="dateCreated">2023-01-01</span><span itemprop="dateModified">2022-01-01</span>
            <span itemprop="uploadDate">2021-01-01</span>
            <span itemprop="headline">Created</span><a itemprop="url" href="/created">Open</a>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="dateModified">2022-01-01</span><span itemprop="uploadDate">2021-01-01</span>
            <span itemprop="headline">Modified</span><a itemprop="url" href="/modified">Open</a>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="uploadDate">2021-01-01</span>
            <span itemprop="headline">Uploaded</span><a itemprop="url" href="/uploaded">Open</a>
          </article>
        HTML
      end

      it 'prefers datePublished, dateCreated, dateModified, then uploadDate' do
        expect(articles.map { _1[:published_at] }).to eq(%w[2024-01-01 2023-01-01 2022-01-01 2021-01-01])
      end
    end

    context 'with competing image properties' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline">Image wins</span>
            <img itemprop="image" src="/first.jpg"><img itemprop="image" src="/second.jpg">
            <meta itemprop="thumbnailUrl" content="/thumb.jpg">
            <a itemprop="url" href="/image">Open</a>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline">Thumbnail fallback</span>
            <meta itemprop="thumbnailUrl" content="https://cdn.example.com/thumb.jpg">
            <a itemprop="url" href="/thumbnail">Open</a>
          </article>
        HTML
      end

      it 'uses the first image, falling back to thumbnailUrl', :aggregate_failures do
        expect(articles.map { _1[:image].to_s }).to eq(['https://example.com/first.jpg', 'https://cdn.example.com/thumb.jpg'])
      end
    end

    context 'with url and identifier fallbacks' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline">Blank url falls through</span>
            <span itemprop="url">   </span>
            <span itemprop="mainEntityOfPage" href="/main-entity"></span>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline">Nested url item</span>
            <div itemprop="url" itemscope itemtype="https://schema.org/WebPage">
              <meta itemprop="url" content="/nested-url">
            </div>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle" itemid="http://example.com/http-itemid">
            <span itemprop="headline">Http itemid</span>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle" itemid="foo https://example.com/not-leading">
            <span itemprop="headline">Itemid with leading text</span>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline">Identifier fallback</span>
            <span itemprop="identifier">/identifier/9</span>
          </article>
        HTML
      end

      let(:expected_urls) do
        %w[
          https://example.com/main-entity
          https://example.com/nested-url
          http://example.com/http-itemid
          https://example.com/identifier/9
        ]
      end

      it 'resolves the url from explicit properties, then URL-like identifiers', :aggregate_failures do
        expect(articles.map { _1[:url].to_s }).to eq(expected_urls)
        expect(articles.map { _1[:id] }).to eq(['/main-entity', '/nested-url', '/http-itemid', '/identifier/9'])
      end
    end

    context 'with property value attributes and text' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline" content="Attribute wins">Text loses</span>
            <span itemprop="description" content="   ">  Text   fallback  </span>
            <data itemprop="keywords" value="data-value"></data>
            <object itemprop="image" data="/object.jpg"></object>
            <a itemprop="url" href="/attributes">Open</a>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline">   </span>
            <span itemprop="description">Description without title</span>
            <a itemprop="url" href="/blank-headline">Open</a>
          </article>
        HTML
      end

      it 'prefers attribute values, strips text, and ignores blank properties', :aggregate_failures do
        expect(articles.first).to include(title: 'Attribute wins', description: 'Text   fallback',
                                          categories: ['data-value'])
        expect(articles.first[:image].to_s).to eq('https://example.com/object.jpg')
        expect(articles.last).not_to have_key(:title)
      end
    end

    context 'with multi-name, repeated, and padded itemprop values' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline name">Shared name</span>
            <span itemprop="  description  ">Padded itemprop</span>
            <a itemprop="url" href="/multi">Open</a>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <h1 itemprop="headline">First headline</h1><h2 itemprop="headline">Second headline</h2>
            <a itemprop="url" href="/repeated">Open</a>
          </article>
        HTML
      end

      it 'assigns one value to every name and keeps the first repeated value', :aggregate_failures do
        expect(articles.first).to include(title: 'Shared name', description: 'Padded itemprop')
        expect(articles.last[:title]).to eq('First headline')
      end
    end

    context 'with repeated category properties' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline">Many categories</span>
            <span itemprop="articleSection">S1</span><span itemprop="articleSection">S2</span>
            <meta itemprop="keywords" content="K1"><meta itemprop="keywords" content="K2">
            <span itemprop="tags">T1</span><span itemprop="tags">T2</span>
            <div itemprop="about" itemscope itemtype="https://schema.org/Thing"><span itemprop="name">A1</span></div>
            <div itemprop="about" itemscope itemtype="https://schema.org/Thing"><span itemprop="name">A2</span></div>
            <a itemprop="url" href="/many">Open</a>
          </article>
        HTML
      end

      it 'keeps every value' do
        expect(articles.first[:categories]).to contain_exactly('S1', 'S2', 'K1', 'K2', 'T1', 'T2', 'A1', 'A2')
      end
    end

    context 'with nested keyword and about items' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline">Nested keywords ignored</span>
            <div itemprop="keywords" itemscope itemtype="https://schema.org/Thing"><span itemprop="name">Hidden</span></div>
            <div itemprop="about" itemscope itemtype="https://schema.org/Thing"><span itemprop="name">Named topic</span></div>
            <div itemprop="about" itemscope itemtype="https://schema.org/Thing"></div>
            <a itemprop="url" href="/nested-keywords">Open</a>
          </article>
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <span itemprop="headline">String about</span>
            <span itemprop="about">Plain topic</span>
            <a itemprop="url" href="/string-about">Open</a>
          </article>
        HTML
      end

      it 'drops nested keyword items and unnamed about items', :aggregate_failures do
        expect(articles.first[:categories]).to eq(['Named topic'])
        expect(articles.last[:categories]).to eq(['Plain topic'])
      end
    end

    context 'with itemtype variants' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/Thing https://schema.org/NewsArticle">
            <h1 itemprop="headline">Several types</h1><a itemprop="url" href="/several">Open</a>
          </article>
          <article itemscope itemtype="/ https://schema.org/Article">
            <h1 itemprop="headline">Empty segment</h1><a itemprop="url" href="/empty-segment">Open</a>
          </article>
          <article itemscope itemtype="NewsArticle">
            <h1 itemprop="headline">Bare type</h1><a itemprop="url" href="/bare">Open</a>
          </article>
        HTML
      end

      it 'accepts any supported type among several itemtype values' do
        expect(articles.map { _1[:title] }).to eq(['Several types', 'Empty segment', 'Bare type'])
      end
    end

    context 'with ancestors around top-level items' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <div itemscope itemtype="https://schema.org/Person">
            <article itemscope itemtype="https://schema.org/NewsArticle">
              <h1 itemprop="headline">Inside unscoped item</h1><a itemprop="url" href="/inside-item">Open</a>
            </article>
          </div>
          <div itemprop="mainEntity">
            <article itemscope itemtype="https://schema.org/NewsArticle">
              <h1 itemprop="headline">Inside itemprop wrapper</h1><a itemprop="url" href="/inside-wrapper">Open</a>
            </article>
          </div>
          <div itemscope itemprop="outer">
            <div>
              <article itemscope itemtype="https://schema.org/NewsArticle">
                <h1 itemprop="headline">Inside nested item</h1><a itemprop="url" href="/inside-nested">Open</a>
              </article>
            </div>
          </div>
        HTML
      end

      it 'emits roots unless an itemscope ancestor carries an itemprop' do
        expect(articles.map { _1[:title] }).to eq(['Inside unscoped item', 'Inside itemprop wrapper'])
      end
    end

    context 'with article microdata' do
      let(:expected_article) do
        {
          id: '/stories/microdata-headline',
          title: 'Microdata headline',
          description: 'Longer body copy for the story.',
          url: Html2rss::Url.from_relative('/stories/microdata-headline', base_url),
          image: Html2rss::Url.from_relative('/images/microdata-headline.jpg', base_url),
          published_at: '2024-03-09T10:30:00Z',
          categories: %w[Politics Europe World Elections]
        }
      end

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle" itemid="https://example.com/stories/microdata-headline">
            <h1 itemprop="headline">Microdata headline</h1>
            <a itemprop="url" href="/stories/microdata-headline">Read more</a>
            <p itemprop="description">Lead summary.</p>
            <div itemprop="articleBody">Longer body copy for the story.</div>
            <img itemprop="image" src="/images/microdata-headline.jpg" alt="">
            <time itemprop="datePublished" datetime="2024-03-09T10:30:00Z">March 9</time>
            <meta itemprop="keywords" content="Politics, Europe">
            <span itemprop="articleSection">World</span>
            <div itemprop="about" itemscope itemtype="https://schema.org/Thing">
              <span itemprop="name">Elections</span>
            </div>
            <span itemprop="author" itemscope itemtype="https://schema.org/Person">
              <span itemprop="name">Jane Doe</span>
            </span>
          </article>
        HTML
      end

      it 'extracts a normalized article hash' do
        expect(articles).to contain_exactly(a_hash_including(expected_article))
      end
    end

    context 'with product microdata' do
      let(:expected_product) do
        {
          id: 'sku-123',
          title: 'Microdata Product',
          description: 'Useful product description.',
          url: Html2rss::Url.from_relative('/products/microdata-product', base_url),
          image: Html2rss::Url.from_absolute('https://cdn.example.com/microdata-product.jpg')
        }
      end

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <section itemscope itemtype="https://schema.org/Product" itemid="sku-123">
            <h2 itemprop="name">Microdata Product</h2>
            <a itemprop="url" href="/products/microdata-product">Open</a>
            <meta itemprop="description" content="Useful product description.">
            <div itemprop="image" itemscope itemtype="https://schema.org/ImageObject">
              <meta itemprop="url" content="https://cdn.example.com/microdata-product.jpg">
            </div>
          </section>
        HTML
      end

      it 'supports Product roots as article-like results' do
        expect(articles).to contain_exactly(a_hash_including(expected_product))
      end
    end

    context 'with an opaque itemid and no explicit url' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <section itemscope itemtype="https://schema.org/Product" itemid="sku-123">
            <h2 itemprop="name">Microdata Product</h2>
            <meta itemprop="description" content="Useful product description.">
          </section>
        HTML
      end

      it 'filters the item out instead of treating itemid as a URL' do
        expect(articles).to eq([])
      end
    end

    context 'with a root-relative itemid and no explicit url' do
      let(:expected_article) do
        a_hash_including(
          id: '/stories/fallback-id',
          url: Html2rss::Url.from_relative('/stories/fallback-id', base_url)
        )
      end

      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/Article" itemid="/stories/fallback-id">
            <h2 itemprop="headline">Fallback item id</h2>
            <p itemprop="description">Uses itemid as a relative URL fallback.</p>
          </article>
        HTML
      end

      it 'uses the itemid as a URL fallback when it is URL-like' do
        expect(articles).to contain_exactly(expected_article)
      end
    end

    context 'with nested supported microdata inside another item property' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <div itemscope itemtype="https://schema.org/ItemList">
            <article itemprop="itemListElement" itemscope itemtype="https://schema.org/Article">
              <h2 itemprop="headline">Nested article</h2>
              <a itemprop="url" href="/nested-article">Open</a>
            </article>
          </div>
        HTML
      end

      it 'does not emit nested property items as top-level articles' do
        expect(articles).to eq([])
      end
    end

    context 'with a nested VideoObject' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <article itemscope itemtype="https://schema.org/NewsArticle">
            <h1 itemprop="headline">Story</h1>
            <a itemprop="url" href="/stories/s">Read</a>
            <div itemprop="video" itemscope itemtype="https://schema.org/VideoObject">
              <meta itemprop="contentUrl" content="/media/s.mp4">
              <meta itemprop="encodingFormat" content="video/mp4">
            </div>
          </article>
        HTML
      end

      it 'emits a video enclosure' do
        enclosure = articles.first[:enclosures].first
        expect([enclosure[:url].to_s, enclosure[:type]]).to eq(['https://example.com/media/s.mp4', 'video/mp4'])
      end
    end
  end
end
