RSpec.describe Html2rss::AttributePostProcessors::ParseUri do
  context 'with URI value' do
    subject { described_class.new(URI('http://example.com'), nil, nil).get }

    it { is_expected.to eq 'http://example.com' }
  end

  context 'with String value' do
    subject { described_class.new('http://example.com', nil, nil).get }

    it { is_expected.to eq 'http://example.com' }
  end
end
