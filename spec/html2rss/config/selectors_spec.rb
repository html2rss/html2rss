# frozen_string_literal: true

RSpec.describe Html2rss::Config::Selectors do
  let(:instance) { described_class.new(selectors: {}) }

  describe '#category_selectors' do
    subject { instance.category_selectors }

    it { is_expected.to be_a(Array) }
  end

  describe '#guid_selectors' do
    subject { instance.guid_selectors }

    it { is_expected.to be_a(Array) }
  end

  describe '#attribute_names' do
    subject { instance.attribute_names }

    it { is_expected.to be_a(Array) }
  end
end
