RSpec.describe Html2rss::ItemExtractors::Html do
  let(:xml) { Nokogiri::HTML('<p>Lorem <b>ipsum</b> dolor ...</p>') }
  let(:options) { { 'selector' => 'p' } }
  subject { described_class.new(xml, options).get }

  it { is_expected.to eq '<p>Lorem <b>ipsum</b> dolor ...</p>' }
end
