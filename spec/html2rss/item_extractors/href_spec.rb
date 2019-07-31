RSpec.describe Html2rss::ItemExtractors::Href do
  subject { described_class.new(xml, options).get }

  let(:options) { { 'selector' => 'a', 'channel' => { 'url' => 'https://example.com' } } }

  context 'with relative href url' do
    let(:xml) { Nokogiri::HTML('<div><a href="/posts/latest-findings">...</a></div>') }

    it { is_expected.to be_a(URI::HTTPS) }
    it { is_expected.to eq URI('https://example.com/posts/latest-findings') }
  end

  context 'with absolute href url' do
    let(:xml) { Nokogiri::HTML('<div><a href="http://example.com/posts/absolute">...</a></div>') }

    it { is_expected.to be_a(URI::HTTP) }
    it { is_expected.to eq URI('http://example.com/posts/absolute') }
  end
end
