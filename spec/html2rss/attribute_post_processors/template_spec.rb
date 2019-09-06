RSpec.describe Html2rss::AttributePostProcessors::Template do
  subject { described_class.new('Hi', options: options, item: item).get }

  let(:options) { { 'string' => '%s! %s is %s! %s', 'methods' => %w[self name autor returns_nil] } }

  # An instance_double does not work with method_missing.
  # rubocop:disable RSpec/VerifiedDoubles
  let(:item) { double(Html2rss::Item) }
  # rubocop:enable RSpec/VerifiedDoubles

  before do
    allow(item).to receive(:name).and_return('My name')
    allow(item).to receive(:autor).and_return('Slim Shady')
    allow(item).to receive(:returns_nil).and_return(nil)
  end

  it { is_expected.to eq 'Hi! My name is Slim Shady! ' }
end
