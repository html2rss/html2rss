# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::ArticleRules::UrlDate do
  describe '.call' do
    let(:now) { Time.utc(2026, 11, 20, 12) }

    before { allow(Html2rss::AutoSource::ArticleRules::Date).to receive(:local_today).and_return(Date.new(2026, 11, 20)) }

    fixture = File.join(__dir__, '../../../../fixtures/link_destination/newspaper4k_pubdate_urls.txt')
    File.readlines(fixture, chomp: true).grep_v(/\A#/).reject(&:empty?).map { _1.split(' ', 2) }.each do |label, url|
      it "labels #{url} as #{label == '1' ? 'dated' : 'undated'}" do
        expect(!described_class.call(url, time_zone: 'UTC', now:).nil?).to eq(label == '1')
      end
    end

    {
      'https://e.com/2026/11/20/slug' => '2026-11-20',
      'https://e.com/2026-11-20-slug' => '2026-11-20',
      'https://e.com/news/2026_11_05/slug' => '2026-11-05',
      'https://e.com/2026/1/5/slug' => '2026-01-05',
      'https://e.com/2026-11-20/slug' => '2026-11-20',
      'https://e.com/2026/11/21/slug' => '2026-11-21',
      'https://e.com/2026/11/20/x-2026-11-20' => '2026-11-20',
      'https://e.com/1995/01/02/slug' => '1995-01-02',
      'https://e.com/2026/11/20/2026-11-20-slug' => '2026-11-20',
      'https://e.com/2026/11/20/日本語-スラッグ' => '2026-11-20',
      'https://e.com/2026/11/20/%E6%97%A5%E6%9C%AC%E8%AA%9E-%E3%82%B9%E3%83%A9%E3%83%83%E3%82%B0' => '2026-11-20',
      'https://e.com/2026/11/20/%D9%85%D9%82%D8%A7%D9%84%D8%A9-%D8%AC%D8%AF%D9%8A%D8%AF%D8%A9' => '2026-11-20',
      'https://e.com/2026-11-20-%D9%85%D9%82%D8%A7%D9%84%D8%A9' => '2026-11-20',
      'https://日本語.example/2026/11/20/slug' => '2026-11-20',
      'https://xn--wgv71a119e.example/2026/11/20/slug' => '2026-11-20'
    }.each do |url, iso|
      it "reads #{iso} from #{url}" do
        expect(described_class.call(url, time_zone: 'UTC', now:).to_date.iso8601).to eq(iso)
      end
    end

    [
      'https://e.com/58201224-219/slug',
      'https://e.com/2020/06/88083',
      'https://e.com/2026/11/22/future',
      'https://e.com/1994/12/31/old',
      'https://e.com/2026/13/01/bad-month',
      'https://e.com/2026/02/30/bad-day',
      'https://e.com/2025/01/02/vs/2025/03/04/two-dates',
      'https://e.com/11/20/2026/slug',
      'https://e.com/slug?d=2026-11-20',
      'https://e.com/2026/11/2012/slug',
      'https://e.com/2026/11/20/2025/01/02/slug',
      'https://e.com/news/2024/01/01/',
      'https://e.com/news/2024/01/01',
      'https://e.com/shop/sku-2023-10-15-blue',
      'https://e.com/shop/a2023-10-15-blue',
      'https://e.com/2026-11-20.html',
      'https://e.com/2026-11-20-',
      'https://e.com/2024/05/10-best-laptops',
      'https://e.com/2024/05/5-ways-to-save',
      'https://e.com/docs/2024.1.2-release-notes',
      'https://e.com/2026/11-20-slug',
      'https://e.com/2026-1-5-slug',
      'https://e.com/2026-11-20',
      'https://e.com/2026%2F11%2F20/slug',
      'https://e.com/2026/11%2F20/slug',
      'https://e.com/2026/11/20%2Fslug'
    ].each do |url|
      it "yields nothing for #{url}" do
        expect(described_class.call(url, time_zone: 'UTC', now:)).to be_nil
      end
    end

    it 'ignores digit-led segments that are not calendar years (unlike the routing shape)', :aggregate_failures do
      expect(described_class.call('https://e.com/9999/01/01/slug', time_zone: 'UTC', now:)).to be_nil
      expect(described_class.call('https://e.com/58201224/slug', time_zone: 'UTC', now:)).to be_nil
    end

    it 'yields nothing for an invalid or opaque uri', :aggregate_failures do
      expect(described_class.call('https://e.com/a?next=/2026/11/20/slug', time_zone: 'UTC', now:)).to be_nil
      expect(described_class.call('https://2026-11-20-x.example.com/a', time_zone: 'UTC', now:)).to be_nil
      expect(described_class.call('/2026/11/20/relative', time_zone: 'UTC', now:)).to be_nil
      expect(described_class.call('', time_zone: 'UTC', now:)).to be_nil
      expect(described_class.call('mailto:a@b.c', time_zone: 'UTC', now:)).to be_nil
    end

    it 'judges the future bound against today in the configured time zone', :aggregate_failures do
      zone = 'Pacific/Kiritimati'
      allow(Html2rss::AutoSource::ArticleRules::Date).to receive(:local_today)
        .with(time_zone: zone, now:).and_return(Date.new(2026, 11, 21))

      expect(described_class.call('https://e.com/2026/11/22/a', time_zone: zone, now:)).not_to be_nil
      expect(described_class.call('https://e.com/2026/11/23/a', time_zone: zone, now:)).to be_nil
    end

    it 'returns nil for nil' do
      expect(described_class.call(nil, time_zone: 'UTC', now:)).to be_nil
    end

    it 'accepts an Html2rss::Url' do
      expect(described_class.call(Html2rss::Url.from_relative('/2026/11/20/a', 'https://e.com'),
                                  time_zone: 'UTC', now:).to_date)
        .to eq(Date.new(2026, 11, 20))
    end

    it 'is local midnight in the configured time zone', :aggregate_failures do
      result = described_class.call('https://e.com/2026/11/20/a', time_zone: 'Europe/Berlin', now:)

      expect([result.hour, result.min, result.sec, result.zone]).to eq([0, 0, 0, '+01:00'])
    end

    it 'localises the same way for strings and Url objects' do
      url = 'https://e.com/2026/11/20/a'
      zoned = described_class.call(Html2rss::Url.from_relative(url, 'https://e.com'), time_zone: 'Asia/Tokyo', now:)

      expect(zoned).to eq(described_class.call(url, time_zone: 'Asia/Tokyo', now:))
    end

    it 'defaults to UTC midnight' do
      expect(described_class.call('https://e.com/2026/11/20/a', time_zone: 'UTC', now:).zone).to eq('+00:00')
    end
  end
end
