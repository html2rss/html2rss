# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::SemanticHtml do
  describe '.options_key' do
    specify { expect(described_class.options_key).to eq(:semantic_html) }
  end

  describe '.articles?' do
    let(:parsed_body) do
      Nokogiri::HTML.parse <<~HTML
        <html><body><article><a href="/article-1">Article 1</a></article></body></html>
      HTML
    end

    it 'returns true when there are extractable articles' do
      expect(described_class.articles?(parsed_body)).to be true
    end

    it 'returns false when there are no extractable articles' do
      expect(described_class.articles?(nil)).to be false
    end

    it 'returns false for a parsed document without semantic containers' do
      expect(described_class.articles?(Nokogiri::HTML(''))).to be false
    end
  end

  describe '.request_slots' do
    it 'reserves no request slots regardless of options', :aggregate_failures do
      expect(described_class.request_slots).to eq(0)
      expect(described_class.request_slots(max_pages: 3)).to eq(0)
    end
  end

  describe 'with an empty document' do
    let(:parsed_body) { Nokogiri::HTML('') }

    it 'is not extractable and yields no articles', :aggregate_failures do
      expect(described_class.articles?(parsed_body)).to be false
      expect(described_class.new(parsed_body, url: 'https://example.com').to_a).to eq([])
    end
  end

  describe '#initialize' do
    let(:parsed_body) do
      Nokogiri::HTML.parse <<~HTML
        <html><body><article><a href="/article-1">Article 1</a></article></body></html>
      HTML
    end

    it 'is constructible without raising' do
      expect { described_class.new(parsed_body, url: 'https://example.com') }.not_to raise_error
    end

    it 'drops anchorless containers unless fallback_anchorless is requested' do
      anchorless = Nokogiri::HTML.parse <<~HTML
        <html><body><article><h2>No Link Article</h2><p>Description text</p></article></body></html>
      HTML

      expect(described_class.new(anchorless, url: 'https://example.com').to_a).to eq([])
    end

    context 'with a relative story link and a provided document or link resolver' do
      let(:story_html) do
        <<~HTML
          <html><body><article><h2><a href="/news/relative">Relative story</a></h2>
          <p>Useful context paragraph for readers this week.</p></article></body></html>
        HTML
      end
      let(:provided_document) { Html2rss::SST::Normalizer.call(Nokogiri::HTML.parse(story_html)) }

      it 'resolves relative links against the given url' do
        articles = described_class.new(Nokogiri::HTML.parse(story_html), url: 'https://page.example/').to_a

        expect(articles.map { _1.url.to_s }).to eq(['https://page.example/news/relative'])
      end

      it 'uses a provided SST document even without a parsed body' do
        articles = described_class.new(nil, url: 'https://example.com', document: provided_document).to_a

        expect(articles.map { _1.url.to_s }).to eq(['https://example.com/news/relative'])
      end

      it 'uses a provided link resolver' do
        resolver = Html2rss::Scoring::LinkResolver.new('https://example.com')
        allow(resolver).to receive(:destination_facts).and_call_original

        described_class.new(Nokogiri::HTML.parse(story_html), url: 'https://example.com', link_resolver: resolver).to_a

        expect(resolver).to have_received(:destination_facts).at_least(:once)
      end
    end
  end

  describe '#document' do
    let(:provided_document) do
      Html2rss::SST::Normalizer.call(Nokogiri::HTML.parse(<<~HTML))
        <html><body><article><h2><a href="/news/provided">Provided story</a></h2>
        <p>Useful context paragraph for readers this week.</p></article></body></html>
      HTML
    end

    it 'uses the provided SST document instead of normalizing the body' do
      articles = described_class.new(nil, url: 'https://example.com', document: provided_document).to_a

      expect(articles.map { _1.url.to_s }).to eq(['https://example.com/news/provided'])
    end

    it 'normalizes the parsed body when no document is provided' do
      parsed_body = Nokogiri::HTML.parse(<<~HTML)
        <html><body><article><h2><a href="/news/parsed">Parsed story</a></h2>
        <p>Useful context paragraph for readers this week.</p></article></body></html>
      HTML

      articles = described_class.new(parsed_body, url: 'https://example.com').to_a

      expect(articles.map { _1.url.to_s }).to eq(['https://example.com/news/parsed'])
    end
  end

  describe '#articles' do
    let(:parsed_body) do
      Nokogiri::HTML.parse <<~HTML
        <html><body><article><h2><a href="/news/tagged">Tagged story</a></h2>
        <p>Useful context paragraph for readers this week.</p></article></body></html>
      HTML
    end

    it 'stamps each article with the semantic scraper class', :aggregate_failures do
      articles = described_class.new(parsed_body, url: 'https://example.com').to_a

      expect(articles).not_to be_empty
      expect(articles.map(&:scraper).uniq).to eq([described_class])
    end

    it 'collapses containers that point at the same destination' do
      duplicated = Nokogiri::HTML.parse <<~HTML
        <html><body>
          <article><h2><a href="/news/dup">Duplicate story</a></h2><p>Useful context paragraph for readers.</p></article>
          <article><h2><a href="/news/dup">Duplicate story</a></h2></article>
        </body></html>
      HTML

      articles = described_class.new(duplicated, url: 'https://example.com').to_a

      expect(articles.map { _1.url.to_s }).to eq(['https://example.com/news/dup'])
    end
  end

  describe '#each' do
    subject(:new) { described_class.new(parsed_body, url: 'https://page.com', fallback_anchorless: true) }

    let(:parsed_body) { Nokogiri::HTML.parse(File.read('spec/fixtures/page_1.html')) }
    let(:articles) { new.each.to_a }
    let(:article_ids) { articles.filter_map(&:id) }

    let(:grouped_expected_articles) do
      # rubocop:disable-next Layout/LineLength
      [
        { title: 'Brittney Griner: What I Endured in Russia', url: 'https://page.com/6972085/brittney-griner-book-coming-home/', image: 'https://api.page.com/wp-content/uploads/2024/04/brittney-griner-basketball-russia.jpg?quality=85&w=925&h=617&crop=1&resize=925,617', description: "Chris Coduto—Getty Images\n17 MIN READ\n\"Prison is more than a place. It’s also a mindset,\" Brittney Griner writes in an excerpt from her book about surviving imprisonment in Russia.", id: '/6972085/brittney-griner-book-coming-home/' },
        { title: 'Driver Dies After Crashing Into White House Security Barrier', url: 'https://page.com/6974836/white-house-car-crash-driver-dies-security-barrier/', image: 'https://api.page.com/wp-content/uploads/2024/05/AP24126237101577.jpg?quality=85&w=925&h=617&crop=1&resize=925,617', description: '1 MIN READ', id: '/6974836/white-house-car-crash-driver-dies-security-barrier/' }
      ].group_by { |article| article[:id] }
    end

    it 'yields and includes all expected articles', :aggregate_failures, :slow do # rubocop:disable RSpec/ExampleLength
      new.each do |article|
        expected_article = grouped_expected_articles[article.id]&.shift
        next unless expected_article

        expected_article.each do |key, value|
          expect(article.public_send(key).to_s).to eq(value.to_s)
        end
      end
      expect(grouped_expected_articles.values.flatten).to be_empty
    end

    it 'keeps the intended article ids on the large semantic fixture', :aggregate_failures, :slow do
      expect(article_ids).to include('/6972085/brittney-griner-book-coming-home/')
      expect(article_ids).to include('/6974836/white-house-car-crash-driver-dies-security-barrier/')
    end

    it 'keeps noisy newsletter and author links out of the large semantic fixture', :slow do
      excluded_ids = [
        'https://cloud.newsletters.page.com/signup?nln=worth-your-page',
        'https://page.com/author/eddie-s-glaude-jr/'
      ]

      expect(article_ids & excluded_ids).to be_empty
    end

    it 'keeps a useful recall floor on the large semantic fixture', :aggregate_failures, :slow do
      expect(articles.size).to be >= 60
      expect(articles.size).to be < 100
    end

    context 'when fallback_anchorless is true and page has no anchors' do
      subject(:new) { described_class.new(parsed_body, url: 'https://page.com', fallback_anchorless: true) }

      let(:parsed_body) do
        Nokogiri::HTML.parse <<~HTML
          <html>
            <body>
              <article>
                <h2>No Link Article 1</h2>
                <p>Description text 1</p>
              </article>
              <article>
                <h2>No Link Article 2</h2>
                <p>Description text 2</p>
              </article>
            </body>
          </html>
        HTML
      end

      it 'extracts semantic articles anchorlessly', :aggregate_failures do
        expect(articles.size).to eq(2)
        expect(articles.first.title).to eq('No Link Article 1')
        expect(articles.first.url.to_s).to eq('https://page.com/#no-link-article-1')
        expect(articles.last.title).to eq('No Link Article 2')
        expect(articles.last.url.to_s).to eq('https://page.com/#no-link-article-2')
      end
    end
  end
end
