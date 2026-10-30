# frozen_string_literal: true

RSpec.describe Html2rss::Test::QualityReport do
  let(:audit) do
    Html2rss::AutoSource::Cleanup::AuditResult.new(warnings: [:duplicate_urls], metrics: { item_count: 2 },
                                                   violations: {})
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
