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
  end

  describe '#each' do
    subject(:new) { described_class.new(parsed_body, url: 'https://page.com') }

    let(:parsed_body) { Nokogiri::HTML.parse(File.read('spec/fixtures/page_1.html')) }
    let(:articles) { new.each.to_a }
    let(:article_ids) { articles.filter_map { |article| article[:id] } }

    let(:grouped_expected_articles) do
      # rubocop:disable Layout/LineLength
      [
        { title: 'Brittney Griner: What I Endured in Russia', url: 'https://page.com/6972085/brittney-griner-book-coming-home/', image: 'https://api.PAGE.com/wp-content/uploads/2024/04/brittney-griner-basketball-russia.jpg?quality=85&w=925&h=617&crop=1&resize=925,617', description: "Chris Coduto—Getty Images\n17 MIN READ\nMay 3, 2024 • 8:00 AM EDT\n\"Prison is more than a place. It’s also a mindset,\" Brittney Griner writes in an excerpt from her book about surviving imprisonment in Russia.", id: '/6972085/brittney-griner-book-coming-home/' },
        { title: 'Driver Dies After Crashing Into White House Security Barrier', url: 'https://page.com/6974836/white-house-car-crash-driver-dies-security-barrier/', image: 'https://api.PAGE.com/wp-content/uploads/2024/05/AP24126237101577.jpg?quality=85&w=925&h=617&crop=1&resize=925,617', description: "1 MIN READ\nMay 5, 2024 • 7:46 AM EDT", id: '/6974836/white-house-car-crash-driver-dies-security-barrier/' }
      ].group_by { |article| article[:id] }
      # rubocop:enable Layout/LineLength
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

    it 'reduces raw candidate volume on the large semantic fixture', :slow do
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
        expect(articles.first[:title]).to eq('No Link Article 1')
        expect(articles.first[:url].to_s).to eq('https://page.com/#no-link-article-1')
        expect(articles.last[:title]).to eq('No Link Article 2')
        expect(articles.last[:url].to_s).to eq('https://page.com/#no-link-article-2')
      end
    end
  end
end
