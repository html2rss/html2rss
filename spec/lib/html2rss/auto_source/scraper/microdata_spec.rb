# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Microdata do
  subject(:scraper) { described_class.new(parsed_body, url: base_url) }

  let(:base_url) { Html2rss::Url.from_relative('https://example.com', 'https://example.com') }

  describe '.options_key' do
    it { expect(described_class.options_key).to eq(:microdata) }
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

    context 'with article microdata' do
      let(:expected_article) do
        {
          id: 'https://example.com/stories/microdata-headline',
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
          image: Html2rss::Url.from_relative('https://cdn.example.com/microdata-product.jpg', base_url)
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
  end
end
