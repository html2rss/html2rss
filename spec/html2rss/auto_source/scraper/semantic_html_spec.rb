# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::SemanticHtml do
  let(:parsed_body) { Nokogiri::HTML.parse(File.read('spec/fixtures/page_1.html')) }

  describe '.articles?' do
    it 'returns true when there are extractable articles' do
      expect(described_class.articles?(parsed_body)).to be true
    end

    it 'returns false when there are no extractable articles' do
      expect(described_class.articles?(Nokogiri::HTML.parse(''))).to be false
    end
  end

  describe '#call' do
    subject(:articles) { described_class.new(parsed_body, url: 'https://page.com').call }

    let(:expected_articles) do
      # rubocop:disable Metrics/LineLength
      [
        { title: 'Brittney Griner: What I Endured in Russia', url: Addressable::URI, image: nil, description: '17 MIN READ May 3, 2024 • 8:00 AM EDT "Prison is more than a place. It’s also a mindset," Brittney Griner writes in an excerpt from her book about surviving imprisonment in Russia.', id: '/6972085/brittney-griner-book-coming-home/' },
        { title: 'How Far Trump Would Go', url: Addressable::URI, image: nil, description: '26 MIN READ April 30, 2024 • 7:00 AM EDT', id: '/6972021/donald-trump-2024-election-interview/' },
        { title: 'The Kristi Noem and Kim Jong Un Controversy, Explained', url: Addressable::URI, image: nil, description: '3 MIN READ May 5, 2024 • 8:18 AM EDT', id: '/6974797/kristi-noem-kim-jong-un-book-controversy/' },
        { title: 'Driver Dies After Crashing Into White House Security Barrier', url: Addressable::URI, image: nil, description: '1 MIN READ May 5, 2024 • 7:46 AM EDT', id: '/6974836/white-house-car-crash-driver-dies-security-barrier/' }
      ]
      # rubocop:enable Metrics/LineLength
    end

    it 'returns also the expected articles', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      expected_articles.each do |expected_article|
        article = articles.find { |a| a[:title] == expected_article[:title] }

        expected_article.each do |key, value|
          if key == :url
            expect(article[key]).to be_a(Addressable::URI),
                                    lambda {
                                      "Expected #{key} to be an Addressable::URI, but was #{article[key]}"
                                    }
          else
            expect(article[key]).to eq(value),
                                    -> { "Expected #{key} to be #{value}, but was #{article[key].inspect}" }
          end
        end
      end
    end

    it 'returns the expected number of articles' do
      # Many articles are extracted from the page, but only 3 are expected [above].
      # The SemanticHtml class tries to catch as many article as possibile.
      # RSS readers respecting the items' guid will only show the other articles once.
      #
      # However, to catch larger changes in the algorithm, the number of articles is expected.
      expect(articles.size).to be_within(460).of(expected_articles.size)
    end

    it 'returns an array of articles' do
      expect(articles).to be_an(Array) & all(be_a(Hash))
    end

    it 'extracts articles with valid URLs' do
      articles.each do |article|
        expect(article[:url]).to be_a(Addressable::URI)
      end
    end
  end

  describe '.find_article_tag' do
    let(:html) do
      <<-HTML
        <body>
          <article>
            <p>
              <a href="#" id="link">Link</a>
            </p>
          </article>
        </body>
      HTML
    end

    let(:document) { Nokogiri::HTML(html) }
    let(:anchor) { document.at_css('#link') }

    context 'when the anchor is inside the specified tag' do
      it 'returns the specified tag' do
        article_tag = described_class.find_article_tag(anchor, 'article')
        expect(article_tag.name).to eq('article')
      end
    end

    context 'when the anchor is not inside the specified tag' do
      it 'returns nil' do
        article_tag = described_class.find_article_tag(anchor, 'section')
        expect(article_tag).to be_nil
      end
    end

    context 'when the anchor is the specified tag' do
      let(:html) do
        <<-HTML
          <article id="link">
            <p>Content</p>
          </article>
        HTML
      end

      it 'returns the anchor itself' do
        article_tag = described_class.find_article_tag(anchor, 'article')
        expect(article_tag).to eq(anchor)
      end
    end
  end

  describe '.tag_and_selector' do
    let(:expected_result) do
      [
        ['article', 'article :not(article) a[href]'],
        ['li', 'ul > li :not(li) a[href]'],
        ['li', 'ol > li :not(li) a[href]']
      ]
    end

    it 'returns an array of tag and selector pairs' do
      expect(described_class.tag_and_selector).to include(*expected_result)
    end

    it 'memoizes the result' do
      first_call = described_class.tag_and_selector
      second_call = described_class.tag_and_selector

      expect(first_call).to equal(second_call)
    end
  end

  describe '.find_closest_anchor' do
    let(:html) do
      <<-HTML
      <body>
        <div id="container">
          <p>
            <a href="#" id="link">Link</a>
          </p>
        </div>
      </body>
      HTML
    end

    let(:document) { Nokogiri::HTML(html) }
    let(:container) { document.at_css('#container') }

    context 'when the anchor is directly within the element' do
      it 'returns the anchor' do
        anchor = described_class.find_closest_anchor(container)
        expect(anchor['id']).to eq('link')
      end
    end

    context 'when the anchor is nested within the element' do
      let(:nested_html) do
        <<-HTML
        <body>
          <div id="container">
            <div>
              <a href="#" id="nested-link">Nested Link</a>
            </div>
          </div>
        </body>
        HTML
      end

      it 'returns the nested anchor' do
        nested_document = Nokogiri::HTML(nested_html)
        nested_container = nested_document.at_css('#container')

        anchor = described_class.find_closest_anchor(nested_container)
        expect(anchor['id']).to eq('nested-link')
      end
    end

    context 'when there is no anchor within the element' do
      let(:no_anchor_container) do
        no_anchor_html = <<-HTML
        <body>
          <div id="container">
            <p>No link here</p>
          </div>
        </body>
        HTML

        Nokogiri::HTML(no_anchor_html).at_css('#container')
      end

      it 'returns nil' do
        anchor = described_class.find_closest_anchor(no_anchor_container)
        expect(anchor).to be_nil
      end
    end
  end

  describe '.find_closest_anchor_upwards' do
    let(:html) do
      <<-HTML
        <div>
          <p>
            <a href="#" id="link">Link</a>
            <span id="span">Span</span>
          </p>
        </div>
      HTML
    end

    let(:document) { Nokogiri::HTML(html) }
    let(:element) { document.at_css('#span') }
    let(:expected_anchor) { document.at_css('a') }

    context 'when an anchor is found in the current element' do
      it 'returns the anchor' do
        anchor = described_class.find_closest_anchor_upwards(element)
        expect(anchor).to eq(expected_anchor)
      end
    end

    context 'when an anchor is not found in the current element' do
      it 'returns the closest anchor in the parent elements' do
        anchor = described_class.find_closest_anchor_upwards(element.parent)
        expect(anchor).to eq(expected_anchor)
      end
    end
  end
end
