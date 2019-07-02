RSpec.describe Html2rss::AttributePostProcessors::Substring do
  context 'with end' do
    subject { described_class.new('Foo bar and baz', { 'start' => 4, 'end' => 6 }, nil).get }
    it { is_expected.to eq 'bar' }
  end

  context 'without end' do
    subject { described_class.new('foobarbaz', { 'start' => 3 }, nil).get }
    it { is_expected.to eq 'barbaz' }
  end
end
