# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::PostProcessors::Template do
  subject { described_class.new('Hi', context).get }

  let(:item) { Object.new }
  let(:item_scope) { instance_double(Html2rss::Selectors::ItemScope) }
  let(:context) { Html2rss::Selectors::Context.new(options:, item:, item_scope:) }

  before do
    allow(item_scope).to receive(:select).with(:name).and_return('My name')
    allow(item_scope).to receive(:select).with(:author).and_return('Slim Shady')
    allow(item_scope).to receive(:select).with(:returns_nil).and_return(nil)
  end

  it { expect(described_class).to be < Html2rss::Selectors::PostProcessors::Base }

  context 'when the string is empty' do
    it 'raises an error' do
      expect do
        described_class.new('', Html2rss::Selectors::Context.new(options: {}, item_scope:))
      end.to raise_error(Html2rss::Selectors::PostProcessors::InvalidType, 'The `string` template is absent.')
    end
  end

  context 'when item_scope is missing' do
    it 'raises MissingOption' do
      expect do
        # rubocop:disable-next Style/FormatStringToken -- template post-processor uses %{key}
        described_class.new('Hi', Html2rss::Selectors::Context.new(options: { string: '%{name}' }))
      end.to raise_error(Html2rss::Selectors::PostProcessors::MissingOption,
                         'The post-processor context is missing `item_scope`.')
    end
  end

  context 'with mixed complex formatting notation' do
    let(:options) { { string: '%{self}! %<name>s is %{author}! %{returns_nil}' } } # rubocop:disable Style/FormatStringToken

    it { is_expected.to eq 'Hi! My name is Slim Shady! ' }
  end

  context 'when routing nested selects through ItemScope' do
    let(:options) { { string: '%{name}' } } # rubocop:disable Style/FormatStringToken

    it 'renders via scope.select', :aggregate_failures do
      expect(subject).to eq('My name')
      expect(item_scope).to have_received(:select).with(:name)
    end
  end
end
