# frozen_string_literal: true

RSpec.describe Html2rss::Item do
  describe '.categories' do
    subject(:instance) { described_class.send(:new, Nokogiri.HTML('<li> Category </li>'), config) }

    let(:config) do
      Html2rss::Config.new(
        channel: { url: 'http://example.com' },
        selectors: {
          items: {},
          foo: { selector: 'li' },
          bar: { selector: 'li' },
          categories: %i[foo bar]
        }
      )
    end

    it 'returns an array of uniq and stripped categories' do
      expect(instance.categories).to eq ['Category']
    end
  end
end
