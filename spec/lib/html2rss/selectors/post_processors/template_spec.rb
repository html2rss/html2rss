# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::PostProcessors::Template do
  subject { described_class.new('Hi', options:, item:, scraper:).get }

  let(:item) { Object.new }
  let(:scraper) { instance_double(Html2rss::Selectors) }

  before do
    allow(scraper).to receive(:select).with(:name, item).and_return('My name')
    allow(scraper).to receive(:select).with(:author, item).and_return('Slim Shady')
    allow(scraper).to receive(:select).with(:returns_nil, item).and_return(nil)
  end

  it { expect(described_class).to be < Html2rss::Selectors::PostProcessors::Base }

  context 'when the string is empty' do
    it 'raises an error' do
      expect do
        described_class.new('', {})
      end.to raise_error(Html2rss::Selectors::PostProcessors::InvalidType, 'The `string` template is absent.')
    end
  end

  context 'with mixed complex formatting notation' do
    let(:options) { { string: '%{self}! %<name>s is %{author}! %{returns_nil}' } } # rubocop:disable Style/FormatStringToken

    it { is_expected.to eq 'Hi! My name is Slim Shady! ' }
  end
end
