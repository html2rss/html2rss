# frozen_string_literal: true

require 'tzinfo'

RSpec.describe Html2rss::Selectors::PostProcessors::ParseTime do
  it { expect(described_class).to be < Html2rss::Selectors::PostProcessors::Base }

  context 'with known time_zone' do
    {
      'America/New_York' => 'Mon, 01 Jul 2019 12:00:00 -0400',
      'Europe/London' => 'Mon, 01 Jul 2019 12:00:00 +0100',
      'Europe/Berlin' => 'Mon, 01 Jul 2019 12:00:00 +0200'
    }.each_pair do |time_zone, expected|
      it "parses in time_zone #{time_zone}" do
        ctx = Html2rss::Selectors::StepEnv.new(time_zone:)

        expect(described_class.new('2019-07-01 12:00', ctx).call).to eq expected
      end
    end
  end

  context 'with unknown time_zone' do
    it 'raises TZInfo::InvalidTimezoneIdentifier' do
      ctx = Html2rss::Selectors::StepEnv.new(time_zone: 'Foobar/Baz')

      expect { described_class.new('2019-07-01 12:00', ctx).call }.to raise_error(TZInfo::InvalidTimezoneIdentifier)
    end
  end

  context 'with nil time_zone' do
    it 'raises ArgumentError' do
      ctx = Html2rss::Selectors::StepEnv.new(time_zone: nil)

      expect { described_class.new('2019-07-01 12:00', ctx).call }
        .to raise_error(ArgumentError, 'time_zone cannot be nil or empty')
    end
  end

  context 'with empty time_zone' do
    it 'raises ArgumentError' do
      ctx = Html2rss::Selectors::StepEnv.new(time_zone: '')

      expect { described_class.new('2019-07-01 12:00', ctx).call }
        .to raise_error(ArgumentError, 'time_zone cannot be nil or empty')
    end
  end

  it 'does not mutate ENV TZ' do
    previous_tz = ENV.fetch('TZ', nil)
    ctx = Html2rss::Selectors::StepEnv.new(time_zone: 'Europe/Berlin')

    described_class.new('2019-07-01 12:00', ctx).call

    expect(ENV.fetch('TZ', nil)).to eq(previous_tz)
  end

  context 'with partial local timestamps' do
    let(:ctx) { Html2rss::Selectors::StepEnv.new(time_zone: 'Europe/Berlin') }

    it 'keeps seconds and drops fractional seconds', :aggregate_failures do
      expect(described_class.new('2019-07-01 12:00:30', ctx).call).to eq('Mon, 01 Jul 2019 12:00:30 +0200')
      expect(described_class.new('2019-07-01 12:00:30.5', ctx).call).to eq('Mon, 01 Jul 2019 12:00:30 +0200')
    end

    it 'defaults missing minutes and time of day to zero', :aggregate_failures do
      expect(described_class.new('2019-07-01 12:34', ctx).call).to eq('Mon, 01 Jul 2019 12:34:00 +0200')
      expect(described_class.new('2019-07-01', ctx).call).to eq('Mon, 01 Jul 2019 00:00:00 +0200')
    end
  end

  it 'rejects a source string without a date' do
    ctx = Html2rss::Selectors::StepEnv.new(time_zone: 'Europe/Berlin')

    expect { described_class.new('10:00', ctx).call }.to raise_error(ArgumentError, 'year must be an Integer')
  end

  it 'rejects a non-String time_zone with the option name in the message' do
    ctx = Html2rss::Selectors::StepEnv.new(time_zone: ['Europe/Berlin'])

    expect { described_class.new('2019-07-01 12:00', ctx).call }
      .to raise_error(Html2rss::Selectors::PostProcessors::InvalidType, /`time_zone`/)
  end

  it 'exports the parse_time name and description', :aggregate_failures do
    fragment = described_class.schema_export

    expect(fragment.fetch(:properties).fetch(:name)).to eq(type: 'string', const: 'parse_time')
    expect(fragment.fetch(:description)).to eq(described_class::DESCRIPTION)
  end

  it 'uses a zone named in the source string instead of the channel time_zone' do
    ctx = Html2rss::Selectors::StepEnv.new(time_zone: 'Europe/Berlin')

    expect(described_class.new('2019-07-01 12:00 UTC', ctx).call).to eq('Mon, 01 Jul 2019 12:00:00 -0000')
  end

  it 'keeps an explicit offset from the source string' do
    ctx = Html2rss::Selectors::StepEnv.new(time_zone: 'Europe/Berlin')

    expect(described_class.new('2019-07-01 12:00:00 +0000', ctx).call)
      .to eq('Mon, 01 Jul 2019 12:00:00 +0000')
  end
end
