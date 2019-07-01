RSpec.describe Html2rss::ItemExtractors::Static do
  let(:options) { { 'static' => 'Foobar' } }
  subject { described_class.new(nil, options).get }

  it { is_expected.to eq 'Foobar' }
end
