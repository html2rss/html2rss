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

  describe '#each' do
    subject(:new) { described_class.new(parsed_body, url: 'https://page.com') }

    let(:grouped_expected_articles) do
      # rubocop:disable Metrics/LineLength
      [
        { title: 'Brittney Griner: What I Endured in Russia', url: Addressable::URI, image: nil, description: '17 MIN READ May 3, 2024 • 8:00 AM EDT "Prison is more than a place. It’s also a mindset," Brittney Griner writes in an excerpt from her book about surviving imprisonment in Russia.', id: '/6972085/brittney-griner-book-coming-home/' },
        { title: 'How Far Trump Would Go', url: Addressable::URI, image: nil, description: '26 MIN READ April 30, 2024 • 7:00 AM EDT', id: '/6972021/donald-trump-2024-election-interview/' },
        { title: 'The Kristi Noem and Kim Jong Un Controversy, Explained', url: Addressable::URI, image: nil, description: '3 MIN READ May 5, 2024 • 8:18 AM EDT', id: '/6974797/kristi-noem-kim-jong-un-book-controversy/' },
        { title: 'Driver Dies After Crashing Into White House Security Barrier', url: Addressable::URI, image: nil, description: '1 MIN READ May 5, 2024 • 7:46 AM EDT', id: '/6974836/white-house-car-crash-driver-dies-security-barrier/' }
      ].group_by { |article| article[:id] }
      # rubocop:enable Metrics/LineLength
    end

    it 'yields all the expected articles', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      new.each do |article|
        expected_article = grouped_expected_articles[article[:id]]&.shift
        next unless expected_article

        expected_article.each do |key, value|
          if key == :url
            expect(article[key]).to be_a(Addressable::URI),
                                    lambda {
                                      "Expected #{key} to be an Addressable::URI, but was #{article[key]}"
                                    }
          else
            expect(article[key].to_s).to eq(value.to_s),
                                         -> { "Expected #{key} to be #{value}, but was #{article[key].inspect}" }
          end
        end
      end
      expect(grouped_expected_articles.values.flatten).to be_empty
    end

    it 'returns the expected number of articles' do
      # Many articles are extracted from the page, but only 3 are expected [above].
      # The SemanticHtml class tries to catch as many article as possibile.
      # RSS readers respecting the items' guid will only show the other articles once.
      #
      # However, to catch larger changes in the algorithm, the number of articles is expected.
      expect { |b| new.each(&b) }.to yield_control.at_least(333).times
    end
  end

  describe '.find_tag_in_ancestors' do
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
    let(:current_tag) { document.at_css('#link') }

    context 'when the anchor is inside the specified tag' do
      it 'returns the specified tag' do
        article_tag = described_class.find_tag_in_ancestors(current_tag, 'article')
        expect(article_tag.name).to eq('article')
      end
    end

    context 'when the anchor is not inside the specified tag' do
      it 'returns stop_tag' do
        article_tag = described_class.find_tag_in_ancestors(current_tag, 'body')
        expect(article_tag).to be document.at_css('body')
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
        article_tag = described_class.find_tag_in_ancestors(current_tag, 'article')
        expect(article_tag).to eq(current_tag)
      end
    end
  end

  describe '.anchor_tag_selector_pairs' do
    let(:pairs) do
      [
        ['article', 'article :not(article) a[href]'],
        ['li', 'ul > li :not(li) a[href]'],
        ['li', 'ol > li :not(li) a[href]']
      ]
    end

    it 'returns an array of tag and selector pairs' do
      expect(described_class.anchor_tag_selector_pairs).to include(*pairs)
    end
  end

  describe '.find_closest_selector' do
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
        anchor = described_class.find_closest_selector(container)
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

        anchor = described_class.find_closest_selector(nested_container)
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
        anchor = described_class.find_closest_selector(no_anchor_container)
        expect(anchor).to be_nil
      end
    end
  end

  describe '.find_closest_selector_upwards' do
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
        anchor = described_class.find_closest_selector_upwards(element, selector: 'a')
        expect(anchor).to eq(expected_anchor)
      end
    end

    context 'when an anchor is not found in the current element' do
      it 'returns the closest anchor in the parent elements' do
        anchor = described_class.find_closest_selector_upwards(element.parent, selector: 'a')
        expect(anchor).to eq(expected_anchor)
      end
    end
  end
end
