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
      expect { |b| new.each(&b) }.to yield_control.at_least(189).times
    end
  end
end
