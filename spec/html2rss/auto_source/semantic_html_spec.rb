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

    let(:expected_return_value) do
      [
        {
          id: '/6972085/brittney-griner-book-coming-home/',
          title: 'Brittney Griner: What I Endured in Russia',
          url: '/6972085/brittney-griner-book-coming-home/',
          image: 'https://api.PAGE.com/wp-content/uploads/2024/04/brittney-griner-basketball-russia.jpg' \
                 '?quality=85&w=925&h=617&crop=1&resize=925,617',
          description: 'Chris Coduto—Getty Images<br>"Prison is more than a place. ' \
                       'It’s also a mindset," Brittney Griner writes in an excerpt ' \
                       'from her book about surviving imprisonment in Russia.'
        },
        {
          id: '/6972021/donald-trump-2024-election-interview/',
          title: 'How Far Trump Would Go',
          url: '/6972021/donald-trump-2024-election-interview/',
          image: 'https://api.PAGE.com/wp-content/uploads/2024/04/trump-PAGE-interview-2024-00.jpg' \
                 '?quality=85&w=925&h=617&crop=1&resize=925,617',
          description: '26 MIN READ April 30, 2024 • 7:00 AM EDT'
        },
        {
          id: '/6974797/kristi-noem-kim-jong-un-book-controversy/',
          title: 'The Kristi Noem and Kim Jong Un Controversy, Explained',
          url: '/6974797/kristi-noem-kim-jong-un-book-controversy/',
          image: 'https://api.PAGE.com/wp-content/uploads/2024/05/Untitled-design-4.png' \
                 '?w=925&h=617&crop=1&quality=85&resize=925,617',
          description: '3 MIN READ May 5, 2024 • 8:18 AM EDT'
        },
        {
          id: '/6974836/white-house-car-crash-driver-dies-security-barrier/',
          title: 'Driver Dies After Crashing Into White House Security Barrier',
          url: '/6974836/white-house-car-crash-driver-dies-security-barrier/',
          image: 'https://api.PAGE.com/wp-content/uploads/2024/05/AP24126237101577.jpg' \
                 '?quality=85&w=925&h=617&crop=1&resize=925,617',
          description: '1 MIN READ May 5, 2024 • 7:46 AM EDT'
        }
      ]
    end

    it 'returns the extracted articles' do
      expect(articles).to eq(expected_return_value)
    end
  end
end
