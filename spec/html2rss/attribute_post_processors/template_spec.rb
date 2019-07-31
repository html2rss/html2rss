RSpec.describe Html2rss::AttributePostProcessors::Template do
  subject { described_class.new('Hi', options, item).get }

  let(:options) { { 'string' => '%s! %s is %s!', 'methods' => %w[self name autor] } }

  # An instance_double does not work with method_missing.
  # rubocop:disable RSpec/VerifiedDoubles
  let(:item) { double(Html2rss::Item) }
  # rubocop:enable RSpec/VerifiedDoubles

  before do
    allow(item).to receive(:name).and_return('My name')
    allow(item).to receive(:autor).and_return('Slim Shady')
  end

  it { is_expected.to eq 'Hi! My name is Slim Shady!' }
end
