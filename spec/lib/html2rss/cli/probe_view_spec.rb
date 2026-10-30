# frozen_string_literal: true

RSpec.describe Html2rss::CLI::ProbeView do
  describe '.wire_val' do
    it 'reads symbol keys, then string keys', :aggregate_failures do
      expect(described_class.wire_val({ a: 1, 'a' => 2 }, :a)).to eq(1)
      expect(described_class.wire_val({ 'a' => 2 }, :a)).to eq(2)
      expect(described_class.wire_val({}, :a)).to be_nil
    end

    it 'falls back to the string key when the symbol value is falsey' do
      expect(described_class.wire_val({ a: nil, 'a' => 3 }, :a)).to eq(3)
    end
  end

  describe '.from_wire' do
    it 'maps symbol-keyed inspect payloads', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      view = described_class.from_wire(
        requested_url: 'https://a.test', final_url: 'https://a.test/f', status: 200, surface_category: 'listing',
        articles_count: 4, alternate_feeds: [{ href: 'h' }], strategy: 'default'
      )

      expect(view).to eq(
        described_class.new(requested: 'https://a.test', final: 'https://a.test/f', status: 200, surface: 'listing',
                            articles_count: 4, verdict: nil, native_feed: nil, alternate_feeds: [{ href: 'h' }],
                            notes: [], strategy: 'default')
      )
    end

    it 'maps string-keyed payloads and defaults alternate feeds', :aggregate_failures do
      view = described_class.from_wire('requested_url' => 'u', 'surface_category' => 's', 'articles_count' => 1)

      expect(view).to have_attributes(requested: 'u', surface: 's', articles_count: 1, alternate_feeds: [],
                                      final: nil, status: nil, strategy: nil)
    end
  end

  describe '.from_recon' do
    it 'maps a recon result', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      verdict = Html2rss::Recon::Verdict[:defer]
      result = Html2rss::Recon::Result.new(
        requested_url: Html2rss::Url.from_absolute('https://a.test/x'),
        final_url: Html2rss::Url.from_absolute('https://a.test/y'), status: 403, verdict:,
        native_feed: Html2rss::Url.from_absolute('https://a.test/feed'), surface_category: 'blocked',
        articles_count: 0, scheme_downgrade: false, notes: %w[n], html_bytesize: 1
      )

      expect(described_class.from_recon(result)).to eq(
        described_class.new(requested: 'https://a.test/x', final: 'https://a.test/y', status: 403,
                            surface: 'blocked', articles_count: 0, verdict:, native_feed: 'https://a.test/feed',
                            alternate_feeds: [], notes: %w[n], strategy: nil)
      )
    end

    it 'keeps a missing native feed nil' do
      result = Html2rss::Recon::Result.new(
        requested_url: 'a', final_url: 'b', status: nil, verdict: Html2rss::Recon::Verdict[:drop], native_feed: nil,
        surface_category: nil, articles_count: nil, scheme_downgrade: false, notes: [], html_bytesize: nil
      )

      expect(described_class.from_recon(result).native_feed).to be_nil
    end
  end
end
