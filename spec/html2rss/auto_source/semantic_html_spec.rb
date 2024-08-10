# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::SemanticHtml do
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
    subject(:articles) { described_class.new(parsed_body).call }

    let(:expected_articles) do
      # rubocop:disable Metrics/LineLength
      [
        { title: 'Lede Stories', url: '/6972085/brittney-griner-book-coming-home/', image: 'https://api.PAGE.com/wp-content/uploads/2024/04/brittney-griner-basketball-russia.jpg?quality=85&w=925&h=617&crop=1&resize=925,617', description: 'Chris Coduto—Getty Images<br>"Prison is more than a place. It’s also a mindset," Brittney Griner writes in an excerpt from her book about surviving imprisonment in Russia.<br>1<br>2<br>3<br>4', id: 'lede-stories' },
        { title: 'Queen Elizabeth II Ruled Too Long', url: '/6973948/rethinking-queen-elizabeth-legacy/', image: nil, description: '6 MIN READ May 5, 2024 • 7:00 AM EDT', id: 'queen-elizabeth-ii-ruled-too-long' },
        { title: 'Israel Says Hamas Attacks Crossing Point Into Gaza, Wounding Israelis', url: '/6974856/israel-hamas-attack-crossing-point-gaza-aid-injuries/', image: nil, description: 'Israel Says Hamas Attacks Crossing Point Into Gaza, Wounding Israelis 3 MIN READ May 5, 2024 • 9:46 AM EDT', id: 'israel-says-hamas-attacks-crossing-point-into-gaza,-wounding-israelis-' },
        { title: '25 Arrested at University of Virginia as Campus Protests Continue', url: '/6974818/israel-hamas-war-protesters-university-of-michigan-graduation-ceremony/', image: nil, description: '25 Arrested at University of Virginia as Campus Protests Continue 5 MIN READ May 4, 2024 • 3:31 PM EDT', id: '25-arrested-at-university-of-virginia-as-campus-protests-continue' },
        { title: 'Jane Fonda on How People Can Make Politicians Care', url: '/6967535/jane-fonda-climate-politics-earth-award/', image: 'https://api.PAGE.com/wp-content/uploads/2024/04/Jane-Fonda.jpg?quality=85&w=925&h=617&crop=1&resize=925,617', description: 'Roy Rochlin—Getty Images for PAGE<br>Actress and PAGE Earth Award honoree Jane Fonda urged Americans to leverage their voting power to make politicians care about the climate crisis.', id: '6967535-item' }
      ]
      # rubocop:enable Metrics/LineLength
    end

    it 'returns [not just] the expected articles', :aggregate_failures do
      expect(articles).to include(*expected_articles)
      expect(articles.size).to be > expected_articles.size
    end

    it 'returns the expected number of articles' do
      # Many articles are extracted from the page, but only 5 are expected [above].
      # The SemanticHtml class tries to catch as many article as possibile.
      # RSS readers respecting the items' guid will only show the other articles once.
      #
      # However, to catch larger changes in the algorithm, the number of articles is expected.
      expect(articles.size).to be_within(460).of(expected_articles.size)
    end
  end
end
