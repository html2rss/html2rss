RSpec.describe Html2rss::ItemExtractors::Attribute do
  let(:xml) { Nokogiri::HTML('<div><time datetime="2019-07-01">...</time></div>') }
  let(:options) { { 'selector' => 'time', 'attribute' => 'datetime' } }
  subject { described_class.new(xml, options).get }

  it { is_expected.to eq '2019-07-01' }
end