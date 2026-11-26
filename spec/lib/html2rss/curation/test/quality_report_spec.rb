# frozen_string_literal: true

RSpec.describe Html2rss::Curation::Test::QualityReport do
  let(:audit) do
    Html2rss::Curation::Test::Quality::Audit.new(warnings: [:duplicate_urls], metrics: { item_count: 2 })
  end

  describe '.from_audit' do
    it 'copies audit warnings and metrics without a native feed', :aggregate_failures do
      report = described_class.from_audit(audit)

      expect(report).to have_attributes(warnings: [:duplicate_urls], metrics: { item_count: 2 }, native_feed: nil,
                                        defer_reason: nil)
      expect(report.warnings).to be_frozen
    end

    it 'flags a discovered native feed and defers to it', :aggregate_failures do
      report = described_class.from_audit(audit, native_feed: 'https://e.test/feed')

      expect(report).to have_attributes(warnings: %i[duplicate_urls native_feed_present],
                                        native_feed: 'https://e.test/feed', defer_reason: :native_feed)
      expect(audit.warnings).to eq([:duplicate_urls])
    end

    it 'does not duplicate an existing native_feed_present warning' do
      existing = audit.with(warnings: [:native_feed_present])

      expect(described_class.from_audit(existing, native_feed: 'https://e.test/feed').warnings)
        .to eq([:native_feed_present])
    end
  end

  describe '#amend' do
    let(:report) { described_class.from_audit(audit) }

    it 'appends each warning once and merges metrics', :aggregate_failures do
      amended = report.amend(%i[url_mismatch url_mismatch], { url_mismatch: true })

      expect(amended).to have_attributes(warnings: %i[duplicate_urls url_mismatch],
                                         metrics: { item_count: 2, url_mismatch: true })
      expect(amended.warnings).to be_frozen
    end

    it 'leaves the original untouched' do
      report.amend([:url_mismatch], { url_mismatch: true })

      expect(report).to have_attributes(warnings: [:duplicate_urls], metrics: { item_count: 2 })
    end
  end

  describe '#failure_reasons' do
    it 'reads the strict-quality thresholds from the metrics' do
      report = quality_report_with(item_count: 2, unique_url_count: 1, short_title_count: 1)

      expect(report.failure_reasons).to eq(%i[duplicate_urls short_titles])
    end
  end

  describe '#items_without_url?' do
    it 'is true only when selector items were dropped for having no URL', :aggregate_failures do
      expect(quality_report_with(items_without_url: 2).items_without_url?).to be(true)
      expect(quality_report_with.items_without_url?).to be(false)
    end
  end

  describe '#to_h' do
    it 'stringifies warnings and omits native feed keys when absent' do
      expect(described_class.from_audit(audit).to_h).to eq(warnings: ['duplicate_urls'], metrics: { item_count: 2 })
    end

    it 'includes native feed and stringified defer reason when present' do
      expect(described_class.from_audit(audit, native_feed: 'https://e.test/feed').to_h).to eq(
        warnings: %w[duplicate_urls native_feed_present], metrics: { item_count: 2 },
        native_feed: 'https://e.test/feed', defer_reason: 'native_feed'
      )
    end
  end
end
