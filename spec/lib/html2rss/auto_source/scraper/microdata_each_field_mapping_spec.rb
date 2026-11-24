# frozen_string_literal: true

# Pins Microdata output field by field (id, title, description, author, url, image, published_at,
# categories) so the property-to-field mapping can move without changing feeds.
RSpec.describe Html2rss::AutoSource::Scraper::Microdata, '#each' do
  subject(:articles) { described_class.new(Nokogiri::HTML(html), url: base_url).each.to_a }

  let(:base_url) { Html2rss::Url.from_absolute('https://example.com/base/') }
  let(:article) { articles.first }
  let(:fields) { article.slice(:id, :title, :description, :author, :image, :published_at, :categories) }
  let(:resolved_url) { article[:url].to_s }

  def self.article_html(body, type: 'NewsArticle', attrs: '')
    %(<article itemscope itemtype="https://schema.org/#{type}" #{attrs}>#{body}</article>)
  end

  context 'with itemref' do
    let(:html) do
      ref = self.class.article_html('<span itemprop="headline">Ref</span><a itemprop="url" href="/ref">o</a>',
                                    attrs: 'itemref="x"')
      %(<div id="x"><span itemprop="description">From ref</span></div>#{ref})
    end

    it 'ignores referenced properties', :aggregate_failures do
      expect(fields).to eq(id: '/ref', title: 'Ref', categories: [])
      expect(resolved_url).to eq('https://example.com/ref')
    end
  end

  context 'with repeated properties' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <span itemprop="headline">H1</span><span itemprop="headline">H2</span>
        <span itemprop="description">D1</span><span itemprop="description">Longer D2 here</span>
        <img itemprop="image" src="/a.png"><img itemprop="image" src="/b.png">
        <span itemprop="author">A1</span><span itemprop="author">A2</span>
        <a itemprop="url" href="/m1">o</a><a itemprop="url" href="/m2">o</a>
      BODY
    end

    it 'takes the first title, description, image and url and joins authors', :aggregate_failures do
      expect(fields).to include(id: '/m1', title: 'H1', description: 'D1', author: 'A1, A2')
      expect([fields[:image].to_s, resolved_url]).to eq(%w[https://example.com/a.png https://example.com/m1])
    end
  end

  context 'with meta, link, time, img, a and data value sources' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <meta itemprop="headline" content="Meta head"><link itemprop="url" href="/link-url">
        <time itemprop="datePublished" datetime="2024-01-02T03:04:05Z">Jan 2</time>
        <img itemprop="image" src="/img.png" alt="x"><a itemprop="author" href="/who">Who Name</a>
        <object itemprop="description" data="obj">ignored text</object>
        <data itemprop="keywords" value="dv">dtext</data>
      BODY
    end

    it 'reads the attribute before the text', :aggregate_failures do
      expect(fields).to include(id: '/link-url', title: 'Meta head', description: 'obj', author: '/who',
                                published_at: '2024-01-02T03:04:05Z', categories: ['dv'])
      expect([fields[:image].to_s, resolved_url]).to eq(%w[https://example.com/img.png https://example.com/link-url])
    end
  end

  context 'with relative urls' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <span itemprop="headline">Rel</span><meta itemprop="url" content="../up/x">
        <img itemprop="image" src="//cdn.example.org/i.png">
      BODY
    end

    it 'resolves url and image against the page url', :aggregate_failures do
      expect(fields).to include(id: '/up/x')
      expect([resolved_url, fields[:image].to_s]).to eq(%w[https://example.com/up/x https://cdn.example.org/i.png])
    end
  end

  context 'with a relative mainEntityOfPage and thumbnailUrl' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <span itemprop="headline">Rel main</span><link itemprop="mainEntityOfPage" href="/rel-main">
        <img itemprop="thumbnailUrl" src="t.png">
      BODY
    end

    it 'uses them as url and image', :aggregate_failures do
      expect(fields).to include(id: '/rel-main')
      expect([resolved_url, fields[:image].to_s]).to eq(%w[https://example.com/rel-main https://example.com/base/t.png])
    end
  end

  context 'with whitespace and empty values' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <span itemprop="headline">   Padded   headline
         here </span><span itemprop="description">  </span><meta itemprop="author" content=" ">
        <span itemprop="articleSection"> </span><a itemprop="url" href="/ws">o</a>
      BODY
    end

    it 'trims the title and drops blank fields' do
      expect(fields).to eq(id: '/ws', title: "Padded   headline\n here", categories: [])
    end
  end

  context 'with nested items as scalar values' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <div itemprop="headline" itemscope itemtype="https://schema.org/Thing"><span itemprop="name">Nested</span></div>
        <span itemprop="name">Fallback name</span>
        <div itemprop="description" itemscope><span itemprop="name">NestedDesc</span></div>
        <div itemprop="datePublished" itemscope><span itemprop="name">x</span></div>
        <a itemprop="url" href="/hn">o</a>
      BODY
    end

    it 'skips them for title, description and date' do
      expect(fields).to eq(id: '/hn', title: 'Fallback name', categories: [])
    end
  end

  context 'with a nested item and a plain value in one competing group' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <span itemprop="headline">T</span>
        <div itemprop="description" itemscope><span itemprop="name">NestedDesc</span></div>
        <span itemprop="description">Plain description</span><a itemprop="url" href="/hn2">o</a>
      BODY
    end

    it 'reads only the first value, so a leading nested item leaves no description' do
      expect(fields).to eq(id: '/hn2', title: 'T', categories: [])
    end
  end

  context 'with datePosted only' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <span itemprop="headline">DP</span><meta itemprop="datePosted" content="2024-05-05">
        <a itemprop="url" href="/dp">o</a>
      BODY
    end

    it 'has no published_at' do
      expect(fields).to eq(id: '/dp', title: 'DP', categories: [])
    end
  end

  context 'with delimited category strings' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <span itemprop="headline">KW</span><meta itemprop="keywords" content="a, b; c">
        <span itemprop="articleSection">x,y</span><a itemprop="url" href="/kw">o</a>
      BODY
    end

    it 'splits them on comma, semicolon and pipe' do
      expect(article[:categories]).to eq(%w[a b c x y])
    end
  end

  context 'with title, name and alternativeHeadline' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <span itemprop="name">N</span><span itemprop="title">T</span><span itemprop="alternativeHeadline">Alt</span>
        <a itemprop="url" href="/tn">o</a>
      BODY
    end

    it 'prefers title over name and ignores alternativeHeadline' do
      expect(article[:title]).to eq('T')
    end
  end

  context 'with alternativeHeadline only' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <span itemprop="alternativeHeadline">Alt</span><span itemprop="description">D</span>
        <a itemprop="url" href="/alt">o</a>
      BODY
    end

    it 'has no title' do
      expect(fields).to eq(id: '/alt', description: 'D', categories: [])
    end
  end

  context 'with identifier and itemid' do
    let(:html) do
      [
        self.class.article_html('<span itemprop="headline">Id</span><span itemprop="identifier">abc-1</span>' \
                                '<a itemprop="url" href="/id1">o</a>'),
        self.class.article_html('<span itemprop="headline">Id2</span><span itemprop="identifier">abc-1</span>' \
                                '<a itemprop="url" href="/id2">o</a>', attrs: 'itemid="/the-itemid"')
      ].join
    end

    it 'prefers itemid over identifier for the id' do
      expect(articles.map { _1[:id] }).to eq(['abc-1', '/the-itemid'])
    end
  end

  context 'with non-article types' do
    let(:html) do
      self.class.article_html('<span itemprop="name">Prod</span><a itemprop="url" href="/p">o</a>', type: 'Product') +
        self.class.article_html('<span itemprop="name">Rec</span><a itemprop="url" href="/r">o</a>', type: 'Recipe') +
        self.class.article_html('<span itemprop="name">Per</span><a itemprop="url" href="/pe">o</a>', type: 'Person')
    end

    it 'emits only the supported Product' do
      expect(articles.map { _1[:title] }).to eq(['Prod'])
    end
  end

  context 'with image objects' do
    let(:html) do
      self.class.article_html(<<~BODY) + self.class.article_html(<<~OTHER)
        <span itemprop="headline">IO</span>
        <div itemprop="image" itemscope itemtype="https://schema.org/ImageObject">
          <meta itemprop="url" content="/io.png"></div><a itemprop="url" href="/io">o</a>
      BODY
        <span itemprop="headline">IO2</span>
        <div itemprop="image" itemscope itemtype="https://schema.org/Thing"><meta itemprop="url" content="/thing.png"></div>
        <img itemprop="thumbnail" src="/th.png"><a itemprop="url" href="/io2">o</a>
      OTHER
    end

    it 'reads an ImageObject and does not fall past a non-image object', :aggregate_failures do
      expect(articles.first[:image].to_s).to eq('https://example.com/io.png')
      expect(articles.last[:image]).to be_nil
    end
  end

  context 'with a nested mainEntityOfPage item id' do
    let(:html) do
      self.class.article_html('<span itemprop="headline">UN</span>' \
                              '<div itemprop="mainEntityOfPage" itemscope itemtype="https://schema.org/WebPage" ' \
                              'itemid="/page-id"></div>')
    end

    it 'uses the item id as url' do
      expect([article[:id], resolved_url]).to eq(['/page-id', 'https://example.com/page-id'])
    end
  end

  context 'with description, articleBody and abstract' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <span itemprop="headline">DL</span><span itemprop="description">short</span>
        <span itemprop="articleBody">the much longer body text</span><span itemprop="abstract">mid abs</span>
        <a itemprop="url" href="/dl">o</a>
      BODY
    end

    it 'takes the longest' do
      expect(article[:description]).to eq('the much longer body text')
    end
  end

  context 'with a nested publisher' do
    let(:html) do
      self.class.article_html(<<~BODY)
        <span itemprop="headline">PB</span>
        <div itemprop="publisher" itemscope itemtype="https://schema.org/Organization">
          <span itemprop="name">Pub Org</span></div><a itemprop="url" href="/pb">o</a>
      BODY
    end

    it 'uses the publisher name as author' do
      expect(article[:author]).to eq('Pub Org')
    end
  end
end
