# frozen_string_literal: true

RSpec.describe Html2rss::Config::Selectors do
  let(:instance) { described_class.new({ items: { selector: '' }, categories: ['name', 'name', nil], name: {} }) }

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
end
