# frozen_string_literal: true

RSpec.describe Html2rss::Config::Selectors do
  subject(:instance) { described_class.new(config) }

  let(:config) { { items: { selector: '' }, categories: ['name', 'name', nil], name: {} } }

  describe '::Selector' do
    subject { described_class::Selector }

    it 'has the expected attributes' do
      expect(subject.members).to eq(%i[selector attribute extractor post_process order static content_type])
    end
  end

  describe '#category_selector_names' do
    subject { instance.category_selector_names }

    it { is_expected.to eq Set.new(%i[name]) }
  end

  describe '#guid_selector_names' do
    subject { instance.guid_selector_names }

    it { is_expected.to be_a(Set) }
  end

  describe '#item_selector_names' do
    subject { instance.item_selector_names }

    it { is_expected.to be_a(Set) & include(:categories, :name) }
    it { is_expected.not_to include(described_class::ITEMS_SELECTOR_NAME) }
  end

  describe '#selector' do
    let(:config) { { items: { selector: '.item' }, categories: ['name'], name: { selector: '.name' } } }

    context 'when a valid selector name is provided' do
      it 'returns a Selector object with the selector', :aggregate_failures do
        selector = instance.selector(:name)

        expect(selector).to be_a(Html2rss::Config::Selectors::Selector)
        expect(selector.selector).to eq('.name')
      end
    end

    context 'when an invalid selector name is provided' do
      it 'raises an InvalidSelectorName error' do
        expect { instance.selector(:invalid) }.to raise_error(Html2rss::Config::Selectors::InvalidSelectorName)
      end
    end
  end
end
