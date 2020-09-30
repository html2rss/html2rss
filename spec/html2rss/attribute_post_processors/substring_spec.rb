# frozen_string_literal: true

RSpec.describe Html2rss::AttributePostProcessors::Substring do
  context 'with end' do
    subject { described_class.new('Foo bar and baz', options: { start: 4, end: 6 }).get }

    it { is_expected.to eq 'bar' }
  end

  context 'without end' do
    subject { described_class.new('foobarbaz', options: { start: 3 }).get }

    it { is_expected.to eq 'barbaz' }
  end
end
