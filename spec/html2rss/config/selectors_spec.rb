# frozen_string_literal: true

RSpec.describe Html2rss::Config::Selectors do
  let(:instance) { described_class.new({ items: { selector: '' }, categories: ['name', 'name', nil], name: {} }) }

  describe '#category_selectors' do
    subject { instance.category_selectors }

    it { is_expected.to eq Set.new(%i[name]) }
  end

  describe '#guid_selectors' do
    subject { instance.guid_selectors }

    it { is_expected.to be_a(Set) }
  end

  describe '#attribute_names' do
    subject { instance.attribute_names }

    it { is_expected.to be_a(Set) }
  end
end
