# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::ArticleRules::Date do
  it 'reads a date scattered over fragment lines and strips it from the lines', :aggregate_failures do
    lines = ['November', '25', ',', '2026', '| 20:15 PM', 'Body text stays.']

    expect(described_class.earliest([], leftover_lines: lines).to_s).to start_with('2026-11-25T')
    expect(described_class.without_dates(lines)).to eq(['Body text stays.'])
    expect(described_class.without_dates(nil)).to eq([])
  end

  it 'finds a lone date line wherever it stands among other lines', :aggregate_failures do
    expect(described_class.without_dates(['2026-11-27', 'Body text stays.'])).to eq(['Body text stays.'])
    expect(described_class.without_dates(['Intro line.', '2026-11-27', 'Body text stays.']))
      .to eq(['Intro line.', 'Body text stays.'])
    expect(described_class.without_dates(['Intro line.', 'Other line.', '2026-11-27']))
      .to eq(['Intro line.', 'Other line.'])
  end

  describe '.at_midnight' do
    it 'is local midnight of the day in the time zone' do
      result = described_class.at_midnight(Date.new(2026, 11, 20), time_zone: 'Europe/Berlin')

      expect(result.to_s).to eq('2026-11-20T00:00:00+01:00')
    end
  end

  describe '.local_today' do
    it 'is the current calendar day in the zone, UTC when blank or invalid', :aggregate_failures do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 11, 20, 23, 30))

      expect(described_class.local_today(time_zone: 'Asia/Tokyo')).to eq(Date.new(2026, 11, 21))
      expect(described_class.local_today(time_zone: '')).to eq(Date.new(2026, 11, 20))
      expect(described_class.local_today(time_zone: nil)).to eq(Date.new(2026, 11, 20))
      expect(described_class.local_today(time_zone: 'Not/AZone')).to eq(Date.new(2026, 11, 20))
    end
  end

  describe '.parse_datetime' do
    it 'reads a naive value in the time zone and keeps an explicit offset', :aggregate_failures do
      expect(described_class.parse_datetime('2024-07-12T09:00:00', time_zone: 'Europe/Berlin').iso8601)
        .to eq('2024-07-12T09:00:00+02:00')
      expect(described_class.parse_datetime('2024-07-12T09:00:00Z', time_zone: 'Europe/Berlin').offset).to eq(0)
      expect(described_class.parse_datetime('2024-07-12T09:00:00+0500', time_zone: 'Europe/Berlin').hour).to eq(9)
    end

    it 'keeps the instant of a named zone', :aggregate_failures do
      gmt = described_class.parse_datetime('Fri, 12 Jul 2024 10:00:00 GMT', time_zone: 'Europe/Berlin')
      est = described_class.parse_datetime('2024-07-12 10:00 EST', time_zone: 'Europe/Berlin')
      expect(gmt.iso8601).to eq('2024-07-12T10:00:00+00:00')
      expect(est.iso8601).to eq('2024-07-12T10:00:00-05:00')
    end

    it 'reads text with an unknown zone word or a stray letter in the time zone', :aggregate_failures do
      ['12.07.2024 10:00 Uhr', '2024-07-12 10:00 horas', '2024-07-12 10:00 ET',
       '2024-07-12T10:00:00 Europe/Berlin', '2024-07-12 10:00 h'].each do |text|
        expect(described_class.parse_datetime(text, time_zone: 'Europe/Berlin').iso8601)
          .to eq('2024-07-12T10:00:00+02:00')
      end
    end

    it 'keeps a lowercase z as UTC' do
      expect(described_class.parse_datetime('2024-07-12 10:00 z', time_zone: 'Europe/Berlin').offset).to eq(0)
    end

    it 'returns nil for nil and empty input', :aggregate_failures do
      expect(described_class.parse_datetime(nil, time_zone: nil)).to be_nil
      expect(described_class.parse_datetime('', time_zone: nil)).to be_nil
    end

    it 'reads a naive value as UTC without a time zone', :aggregate_failures do
      expect(described_class.parse_datetime('2024-07-12T09:00:00', time_zone: nil).iso8601)
        .to eq('2024-07-12T09:00:00+00:00')
      expect(described_class.parse_datetime('2024-07-12T09:00:00', time_zone: '').iso8601)
        .to eq('2024-07-12T09:00:00+00:00')
    end

    it 'returns nil for blank, over-long, and unparseable text', :aggregate_failures do
      too_long = "2024-07-12#{' ' * Html2rss::AutoSource::ArticleRules::Description::MAX_DATE_CHARS}"
      expect(described_class.parse_datetime('', time_zone: nil)).to be_nil
      expect(described_class.parse_datetime(too_long, time_zone: nil)).to be_nil
      expect(described_class.parse_datetime('not a date', time_zone: nil)).to be_nil
    end

    it 'accepts text of exactly the maximum length' do
      max = Html2rss::AutoSource::ArticleRules::Description::MAX_DATE_CHARS
      expect(described_class.parse_datetime("2024-07-12#{' ' * (max - 10)}", time_zone: nil)).not_to be_nil
    end
  end

  describe '.earliest' do
    it 'returns the earliest parseable datetime' do
      values = ['2026-03-28T12:00:00Z', 'not-a-date', '2026-01-01T00:00:00Z']
      expect(described_class.earliest(values)).to eq(DateTime.parse('2026-01-01T00:00:00Z'))
    end

    it 'parses date-shaped leftover lines in the channel time zone', :aggregate_failures do
      result = described_class.earliest([], leftover_lines: ['12 March 2024 - News article'],
                                            time_zone: 'Europe/Berlin')

      expect(result.to_date).to eq(Date.new(2024, 3, 12))
      expect(result.zone).to eq('+01:00')
    end

    it 'does not parse long teaser lines as dates' do
      teaser = "On 12 March 2024 the company ordered additional dual-fuel vessels for the Asia route #{'word ' * 40}"
      expect(described_class.earliest([], leftover_lines: [teaser])).to be_nil
    end

    it 'falls back to UTC when the channel time zone is invalid', :aggregate_failures do
      result = described_class.earliest([], leftover_lines: ['12 March 2024'], time_zone: 'Not/AZone')

      expect(result).to be_a(DateTime)
      expect(result.to_date).to eq(Date.new(2024, 3, 12))
      expect(result.zone).to eq('+00:00')
    end

    it 'picks standard time when the local clock time is ambiguous', :aggregate_failures do
      result = described_class.earliest(['2024-10-27T02:30:00'], time_zone: 'Europe/Berlin')

      expect(result).to be_a(DateTime)
      expect(result.zone).to eq('+01:00')
      expect(result.hour).to eq(2)
      expect(result.min).to eq(30)
    end

    it 'falls back to UTC when the local clock time does not exist', :aggregate_failures do
      result = described_class.earliest(['2024-03-31T02:30:00'], time_zone: 'Europe/Berlin')

      expect(result).to be_a(DateTime)
      expect(result.zone).to eq('+00:00')
      expect(result.hour).to eq(2)
      expect(result.min).to eq(30)
    end
  end
end
