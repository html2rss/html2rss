RSpec.describe Html2rss::AttributePostProcessors::ParseTime do
  context 'with String value' do
    subject { described_class.new('2019-07-01 12:00', nil, nil).get }

    it { is_expected.to eq 'Mon, 01 Jul 2019 10:00:00 -0000' }
  end

  context 'with Time value' do
    subject { described_class.new(Time.parse('2019-07-01 12:00'), nil, nil).get }

    it { is_expected.to eq 'Mon, 01 Jul 2019 10:00:00 -0000' }
  end
end
