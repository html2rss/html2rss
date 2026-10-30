# frozen_string_literal: true

RSpec.describe Html2rss::Test::Result do
  subject(:result) do
    described_class.new(
      success: true,
      item_count: 5,
      sample_items: [{ title: 'Item 1', url: 'https://example.com/1', published_at: nil }],
      channel_title: 'Example News',
      channel_url: 'https://example.com/news',
      strategy_used: :default,
      duration_seconds: 0.25,
      validation_issues: nil,
      error_message: nil,
      failure_kind: nil,
      rss: '<rss><channel/></rss>'
    )
  end

  it 'provides helper predicate methods', :aggregate_failures do
    expect(result.valid_schema?).to be(true)
    expect(result.empty_feed?).to be(false)
    expect(result.rss).to include('<rss>')
  end

  it 'serializes to hash cleanly' do # rubocop:disable RSpec/ExampleLength
    expect(result.to_h).to include(
      success: true,
      item_count: 5,
      channel_title: 'Example News',
      strategy_used: :default,
      rss: '<rss><channel/></rss>'
    )
  end

  describe '#to_h' do
    it 'serializes every public field and omits response_body', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      issue = Html2rss::Config::ValidationIssue.new(path: %i[channel url], code: :missing_key, message: 'm',
                                                    expected: nil, actual: nil)
      report = Html2rss::Test::QualityReport.new(warnings: [:x], metrics: { item_count: 1 }, native_feed: nil,
                                                 defer_reason: nil)
      full = described_class.new(
        success: false, item_count: 0, sample_items: [], channel_title: 'T', channel_url: 'https://e.test',
        strategy_used: :default, duration_seconds: 1.5, validation_issues: [issue], error_message: 'bad',
        failure_kind: Html2rss::Test::FailureKind[:schema], rss: 'rss', quality_report: report,
        enhance_compare: { delta: 1 }, response_body: '<html>'
      )

      expect(full.to_h).to eq(
        success: false, item_count: 0, sample_items: [], channel_title: 'T', channel_url: 'https://e.test',
        strategy_used: :default, duration_seconds: 1.5, validation_issues: [issue.to_h], error_message: 'bad',
        failure_kind: :schema, rss: 'rss', quality_report: report.to_h, enhance_compare: { delta: 1 }
      )
    end

    it 'drops nil fields' do
      expect(result.to_h.keys).to eq(%i[success item_count sample_items channel_title channel_url strategy_used
                                        duration_seconds rss])
    end
  end

  describe '#valid_schema?' do
    it 'is false only when validation issues exist', :aggregate_failures do
      issue = Html2rss::Config::ValidationIssue.new(path: [], code: :parse, message: 'm', expected: nil, actual: nil)

      expect(result.with(validation_issues: []).valid_schema?).to be(true)
      expect(result.with(validation_issues: [issue]).valid_schema?).to be(false)
    end
  end

  describe '#empty_feed?' do
    it 'is true only for zero items', :aggregate_failures do
      expect(result.with(item_count: 0).empty_feed?).to be(true)
      expect(result.with(item_count: 1).empty_feed?).to be(false)
    end
  end

  describe '#initialize' do
    it 'defaults the optional fields to nil', :aggregate_failures do
      expect(result).to have_attributes(quality_report: nil, enhance_compare: nil, response_body: nil)
    end
  end
end
