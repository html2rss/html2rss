RSpec.describe Html2rss::ItemExtractors::Text do
  let(:xml) { Nokogiri::HTML('<p>Lorem <b>ipsum</b> dolor ...</p>') }
  let(:options) { { 'selector' => 'p' } }
  subject { described_class.new(xml, options).get }

  it { is_expected.to eq 'Lorem ipsum dolor ...' }
end
