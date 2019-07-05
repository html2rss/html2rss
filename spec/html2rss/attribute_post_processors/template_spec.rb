RSpec.describe Html2rss::AttributePostProcessors::Template do
  let(:options) { { 'string' => '%s! %s is %s!', 'methods' => %w[self name autor] } }
  let(:item) { double(Html2rss::Item) }

  before do
    allow(item).to receive(:name).and_return('My name')
    allow(item).to receive(:autor).and_return('Slim Shady')
  end

  subject { described_class.new('Hi', options, item).get }

  it { is_expected.to eq 'Hi! My name is Slim Shady!' }
end
