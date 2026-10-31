# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::AutoSource::Scraper::Microformats2 do
  let(:url) { 'https://example.com/blog' }

  describe '.options_key' do
    it { expect(described_class.options_key).to eq(:microformats2) }
  end

  describe '.articles?' do
    context 'when h-entry class is present' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><div class="h-entry"><span class="p-name">Title</span></div></body></html>')
      end

      it { expect(described_class.articles?(parsed_body)).to be true }
    end

    context 'when h-entry is part of multi-class attribute' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><article class="post h-entry custom-card"></article></body></html>')
      end

      it { expect(described_class.articles?(parsed_body)).to be true }
    end

    context 'when h-entry class is absent' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><div class="article">Title</div></body></html>')
      end

      it { expect(described_class.articles?(parsed_body)).to be false }
    end

    context 'when parsed_body is nil' do
      it { expect(described_class.articles?(nil)).to be false }
    end
  end

  describe '.request_slots' do
    it 'reserves no request slots for any options', :aggregate_failures do
      expect(described_class.request_slots).to eq(0)
      expect(described_class.request_slots(max_requests: 5)).to eq(0)
    end
  end

  describe '#extractable?' do
    subject(:scraper) { described_class.new(parsed_body, url:) }

    context 'when h-entry markup is present' do
      let(:parsed_body) { Nokogiri::HTML('<html><body><div class="h-entry"></div></body></html>') }

      it { expect(scraper.extractable?).to be true }
    end

    context 'when no h-entry markup is present' do
      let(:parsed_body) { Nokogiri::HTML('<html><body><p>Plain</p></body></html>') }

      it { expect(scraper.extractable?).to be false }
    end
  end

  describe '#each' do
    subject(:scraper) { described_class.new(parsed_body, url:) }

    context 'when page has h-entry elements with full metadata' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html>
            <body>
              <article class="h-entry">
                <h2 class="p-name">Microformats Post Title</h2>
                <a class="u-url" href="/posts/post-1">Permalink</a>
                <div class="e-content"><p>Full content of entry</p></div>
                <img class="u-featured" src="/images/hero.jpg" alt="Hero">
                <span class="p-author h-card"><span class="p-name">Alice Smith</span></span>
                <time class="dt-published" datetime="2026-08-10T15:00:00Z">August 10, 2026</time>
                <a class="p-category" href="/tag/ruby">Ruby</a>
                <a class="p-category" href="/tag/rss">RSS</a>
              </article>
            </body>
          </html>
        HTML
      end

      let(:expected_article) do
        {
          title: 'Microformats Post Title',
          url: Html2rss::Url.from_absolute('https://example.com/posts/post-1'),
          description: '<p>Full content of entry</p>',
          image: 'https://example.com/images/hero.jpg',
          author: 'Alice Smith',
          published_at: '2026-08-10T15:00:00Z',
          categories: %w[Ruby RSS]
        }
      end

      it 'yields extracted article attributes', :aggregate_failures do
        expect(scraper.to_a).to eq([expected_article])
      end
    end

    context 'when h-entry elements lack title and url' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><div class="h-entry"><span>No metadata</span></div></body></html>')
      end

      it 'yields nothing' do
        expect(scraper.to_a).to be_empty
      end
    end

    context 'when entry has only a title' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><div class="h-entry"><span class="p-name">Solo</span></div></body></html>')
      end

      it 'falls back to the page URL and omits other attributes' do
        expect(scraper.to_a).to eq([{ title: 'Solo', url: Html2rss::Url.from_absolute(url) }])
      end
    end

    context 'when entry has only a permalink' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><a class="u-url" href="/posts/only">Link</a></div></body></html>
        HTML
      end

      it 'yields an article without a title' do
        expect(scraper.to_a).to eq([{ url: Html2rss::Url.from_absolute('https://example.com/posts/only') }])
      end
    end

    context 'when entry permalink is empty' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><span class="p-name">T</span><a class="u-url" href="">x</a></div></body></html>
        HTML
      end

      it { expect(scraper.first[:url]).to eq(Html2rss::Url.from_absolute(url)) }
    end

    context 'when title and categories contain surrounding whitespace' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry">
            <span class="p-name">   Padded Title   </span>
            <a class="p-category"> Ruby </a>
            <span class="p-category">   </span>
          </div></body></html>
        HTML
      end

      it 'strips text and drops blank categories', :aggregate_failures do
        expect(scraper.first[:title]).to eq('Padded Title')
        expect(scraper.first[:categories]).to eq(['Ruby'])
      end
    end

    context 'when all categories are blank' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><span class="p-name">T</span><span class="p-category"> </span></div></body></html>
        HTML
      end

      it { expect(scraper.first).not_to have_key(:categories) }
    end

    context 'when title is blank and permalink is present' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><span class="p-name">   </span><a class="u-url" href="/p/1">x</a></div></body></html>
        HTML
      end

      it { expect(scraper.first).not_to have_key(:title) }
    end

    context 'when e-content has surrounding whitespace' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><span class="p-name">T</span>
            <div class="e-content">
              <p>Body</p>
            </div>
          </div></body></html>
        HTML
      end

      it { expect(scraper.first[:description]).to eq('<p>Body</p>') }
    end

    context 'when entry has a p-summary but no e-content' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><span class="p-name">T</span><p class="p-summary">Short summary</p></div></body></html>
        HTML
      end

      it { expect(scraper.first[:description]).to eq('Short summary') }
    end

    context 'when e-content is blank' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><span class="p-name">T</span><div class="e-content">   </div></div></body></html>
        HTML
      end

      it { expect(scraper.first).not_to have_key(:description) }
    end

    context 'when image is provided via u-photo href' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><span class="p-name">T</span><a class="u-photo" href="/photos/p.jpg"></a></div></body></html>
        HTML
      end

      it { expect(scraper.first[:image]).to eq('https://example.com/photos/p.jpg') }
    end

    {
      'author avatar before the photo' => [
        '<span class="p-author h-card"><img class="u-photo" src="/avatar.png"><span class="p-name">Jane</span></span>' \
        '<img class="u-photo" src="/hero.jpg">', 'https://example.com/hero.jpg'
      ],
      'avatar in a nested h-card only' => [
        '<div class="h-card"><img class="u-photo" src="/avatar.png"></div>', nil
      ],
      'photo after the avatar and a featured image' => [
        '<span class="p-author"><img class="u-photo" src="/avatar.png"></span><img class="u-featured" src="/f.jpg">',
        'https://example.com/f.jpg'
      ]
    }.each do |name, (markup, expected)|
      context "with #{name}" do
        let(:parsed_body) do
          Nokogiri::HTML(%(<html><body><div class="h-entry"><span class="p-name">T</span>#{markup}</div></body></html>))
        end

        it 'never uses the author avatar as article image' do
          expect(scraper.first[:image]).to eq(expected)
        end
      end
    end

    context 'when image has an empty src' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><span class="p-name">T</span><img class="u-featured" src=""></div></body></html>
        HTML
      end

      it { expect(scraper.first).not_to have_key(:image) }
    end

    context 'when author is a plain p-author element' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><span class="p-name">T</span><span class="p-author">Bob Plain</span></div></body></html>
        HTML
      end

      it { expect(scraper.first[:author]).to eq('Bob Plain') }
    end

    context 'when published date is only text content' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><span class="p-name">T</span><time class="dt-published">  August 10, 2026  </time></div></body></html>
        HTML
      end

      it { expect(scraper.first[:published_at]).to eq('August 10, 2026') }
    end

    context 'when published datetime attribute has surrounding whitespace' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><span class="p-name">T</span><time class="dt-published" datetime="  2026-08-11  ">Aug 11</time></div></body></html>
        HTML
      end

      it { expect(scraper.first[:published_at]).to eq('2026-08-11') }
    end

    context 'when published date is blank' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body><div class="h-entry"><span class="p-name">T</span><time class="dt-published" datetime=" ">  </time></div></body></html>
        HTML
      end

      it { expect(scraper.first).not_to have_key(:published_at) }
    end

    context 'when page has several h-entry elements' do
      let(:parsed_body) do
        Nokogiri::HTML(<<~HTML)
          <html><body>
            <div class="h-entry"><span class="p-name">First</span></div>
            <div class="h-entry"><span class="p-name">Second</span></div>
          </body></html>
        HTML
      end

      it 'yields each entry in document order' do
        expect(scraper.map { _1[:title] }).to eq(%w[First Second])
      end
    end

    context 'when block is not given' do
      let(:parsed_body) do
        Nokogiri::HTML('<html><body><div class="h-entry"><a class="u-url" href="/1">1</a></div></body></html>')
      end

      it 'returns an enumerator yielding the same articles', :aggregate_failures do
        expect(scraper.each).to be_an(Enumerator)
        expect(scraper.each.to_a).to eq(scraper.to_a)
      end
    end
  end
end
