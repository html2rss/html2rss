# frozen_string_literal: true

RSpec.describe Html2rss::AttributePostProcessors::ParseTime do
  context 'with String value' do
    subject { described_class.new('2019-07-01 12:00', config: config).get }

    let(:config) { Html2rss::Config.new(channel: { time_zone: 'Europe/London' }) }

    it { is_expected.to eq 'Mon, 01 Jul 2019 12:00:00 +0100' }
  end
end
