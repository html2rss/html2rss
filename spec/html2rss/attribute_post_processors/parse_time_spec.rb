# frozen_string_literal: true

RSpec.describe Html2rss::AttributePostProcessors::ParseTime do
  context 'with known time_zone' do
    {
      'America/New_York' => 'Mon, 01 Jul 2019 12:00:00 -0400',
      'Europe/London' => 'Mon, 01 Jul 2019 12:00:00 +0100',
      'Europe/Berlin' => 'Mon, 01 Jul 2019 12:00:00 +0200'
    }.each_pair do |time_zone, expected|
      it "parses in time_zone #{time_zone}" do
        ctx = Html2rss::Item::Context.new(config: instance_double(Html2rss::Config, time_zone: time_zone))

        expect(described_class.new('2019-07-01 12:00', ctx).get).to eq expected
      end
    end
  end

  context 'with unknown time_zone' do
    it 'raises TZInfo::InvalidTimezoneIdentifier' do
      ctx = Html2rss::Item::Context.new(config: instance_double(Html2rss::Config, time_zone: 'Foobar/Baz'))

      expect { described_class.new('2019-07-01 12:00', ctx).get }.to raise_error(TZInfo::InvalidTimezoneIdentifier)
    end
  end
end
