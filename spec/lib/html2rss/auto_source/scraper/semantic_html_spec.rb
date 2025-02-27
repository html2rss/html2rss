# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::SemanticHtml do
  describe '.options_key' do
    specify { expect(described_class.options_key).to eq(:semantic_html) }
  end

  describe '.articles?' do
    let(:parsed_body) do
      Nokogiri::HTML.parse <<~HTML
        <html><body><article><a href="">Article 1</a></article></body></html>
      HTML
    end

    it 'returns true when there are extractable articles' do
      expect(described_class.articles?(parsed_body)).to be true
    end

    it 'returns false when there are no extractable articles' do
      expect(described_class.articles?(nil)).to be false
    end
  end

  describe '#each' do
    subject(:new) { described_class.new(parsed_body, url: 'https://page.com') }

    let(:parsed_body) { Nokogiri::HTML.parse(File.read('spec/fixtures/page_1.html')) }

    let(:grouped_expected_articles) do
      # rubocop:disable Metrics/LineLength
      [
        { title: 'Brittney Griner: What I Endured in Russia', url: 'https://page.com/6972085/brittney-griner-book-coming-home/', image: 'https://api.PAGE.com/wp-content/uploads/2024/04/brittney-griner-basketball-russia.jpg?quality=85&w=925&h=617&crop=1&resize=925,617', description: 'Chris Coduto—Getty Images Brittney Griner: What I Endured in Russia 17 MIN READ May 3, 2024 • 8:00 AM EDT "Prison is more than a place. It’s also a mindset," Brittney Griner writes in an excerpt from her book about surviving imprisonment in Russia.', id: '/6972085/brittney-griner-book-coming-home/' },
        { title: 'Driver Dies After Crashing Into White House Security Barrier', url: 'https://page.com/6974836/white-house-car-crash-driver-dies-security-barrier/', image: 'https://api.PAGE.com/wp-content/uploads/2024/05/AP24126237101577.jpg?quality=85&w=925&h=617&crop=1&resize=925,617', description: 'Driver Dies After Crashing Into White House Security Barrier 1 MIN READ May 5, 2024 • 7:46 AM EDT', id: '/6974836/white-house-car-crash-driver-dies-security-barrier/' }
      ].group_by { |article| article[:id] }
      # rubocop:enable Metrics/LineLength
    end

    it 'yields and includes all expected articles', :aggregate_failures, :slow do # rubocop:disable RSpec/ExampleLength
      new.each do |article|
        expected_article = grouped_expected_articles[article[:id]]&.shift
        next unless expected_article

        expected_article.each do |key, value|
          expect(article[key].to_s).to eq(value.to_s)
        end
      end
      expect(grouped_expected_articles.values.flatten).to be_empty
    end

    it 'returns the expected number of articles', :slow do
      # Many articles are extracted from the page, but only 3 are expected [above].
      # The SemanticHtml class tries to catch as many article as possibile.
      # RSS readers respecting the items' guid will only show the other articles once.
      #
      # However, to catch larger changes in the algorithm, the number of articles is expected.
      expect { |b| new.each(&b) }.to yield_control.at_least(220).times
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
            <span id="span">
              <p>:rocket:</p>
            </span>
          </p>
        </div>
      HTML
    end

    let(:document) { Nokogiri::HTML(html) }

    let(:expected_anchor) { document.at_css('a') }

    context 'when an anchor is sibling to current_tag' do
      let(:current_tag) { document.at_css('#span') }

      it 'returns the closest anchor in as sibling' do
        anchor = described_class.find_closest_selector_upwards(current_tag, selector: 'a')
        expect(anchor).to eq(expected_anchor)
      end
    end

    context 'when an anchor is not below current_tag' do
      let(:current_tag) { document.at_css('p') }

      it 'returns the anchor upwards from current_tag' do
        anchor = described_class.find_closest_selector_upwards(current_tag, selector: 'a')
        expect(anchor).to eq(expected_anchor)
      end
    end
  end
end
