# frozen_string_literal: true

RSpec.describe Html2rss::Test::Policy do
  describe 'Outcome' do
    it 'reports success and failure from passed', :aggregate_failures do
      passed = described_class::Outcome.new(passed: true, failure_kind: nil, error_message: nil)
      failed = described_class::Outcome.new(passed: false, failure_kind: nil, error_message: nil)

      expect([passed.success?, passed.failure?]).to eq([true, false])
      expect([failed.success?, failed.failure?]).to eq([false, true])
    end
  end

  describe '.quality_failure?' do
    {
      'clean metrics' => [{}, false],
      'zero items' => [{ item_count: 0, unique_url_count: 0, junk_title_count: 3, short_title_count: 1 }, false],
      'two items sharing a url' => [{ item_count: 2, unique_url_count: 1 }, true],
      'two items with distinct urls' => [{ item_count: 2, unique_url_count: 2 }, false],
      'one item with one url' => [{ item_count: 1, unique_url_count: 1 }, false],
      'exactly half junk titles' => [{ junk_title_count: 2 }, false],
      'more than half junk titles' => [{ junk_title_count: 3 }, true],
      'one short title' => [{ short_title_count: 1 }, true]
    }.each do |label, (overrides, expected)|
      it "is #{expected} for #{label}" do
        expect(described_class.quality_failure?(quality_report_with(**overrides))).to be(expected)
      end
    end
  end

  describe '.outcome_failure' do
    let(:outcome_failure) do
      lambda do |min_items_passed:, quality_failed:, **overrides|
        described_class.outcome_failure(
          min_items_passed:, quality_failed:, item_count: 2, min_items: 5,
          quality_report: quality_report_with(**overrides)
        )
      end
    end

    it 'returns no failure when both checks pass' do
      expect(outcome_failure.call(min_items_passed: true, quality_failed: false)).to eq([nil, nil])
    end

    it 'names the minimum when too few items were extracted' do
      expect(outcome_failure.call(min_items_passed: false, quality_failed: false)).to eq(
        [Html2rss::Test::FailureKind[:min_items], 'Extracted 2 items (minimum required: 5)']
      )
    end

    it 'prefers min_items over quality' do
      expect(outcome_failure.call(min_items_passed: false, quality_failed: true).first)
        .to eq(Html2rss::Test::FailureKind[:min_items])
    end

    it 'lists every failing quality reason in order' do
      expect(outcome_failure.call(min_items_passed: true, quality_failed: true,
                                  unique_url_count: 1, junk_title_count: 3, short_title_count: 1)).to eq(
                                    [Html2rss::Test::FailureKind[:quality],
                                     'Feed quality check failed (duplicate_urls, generic_titles, short_titles)']
                                  )
    end

    it 'lists only the failing quality reasons' do
      expect(outcome_failure.call(min_items_passed: true, quality_failed: true, short_title_count: 2).last)
        .to eq('Feed quality check failed (short_titles)')
    end
  end

  describe '.evaluate' do
    let(:evaluate) do
      lambda do |item_count: 4, min_items: 1, strict_quality: false, **overrides|
        described_class.evaluate(item_count:, min_items:, strict_quality:,
                                 quality_report: quality_report_with(**overrides))
      end
    end

    it 'passes at exactly min_items', :aggregate_failures do
      outcome = evaluate.call(item_count: 3, min_items: 3)

      expect(outcome).to have_attributes(passed: true, failure_kind: nil, error_message: nil)
    end

    it 'fails below min_items', :aggregate_failures do
      outcome = evaluate.call(item_count: 2, min_items: 3, strict_quality: true, short_title_count: 1)

      expect(outcome).to have_attributes(
        passed: false, failure_kind: Html2rss::Test::FailureKind[:min_items],
        error_message: 'Extracted 2 items (minimum required: 3)'
      )
    end

    it 'ignores quality problems unless strict_quality is set' do
      expect(evaluate.call(short_title_count: 1).passed).to be(true)
    end

    it 'fails strict quality and logs it', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(Html2rss::Log).to receive(:info)
      outcome = evaluate.call(strict_quality: true, short_title_count: 1)

      expect(outcome).to have_attributes(
        passed: false, failure_kind: Html2rss::Test::FailureKind[:quality],
        error_message: 'Feed quality check failed (short_titles)'
      )
      expect(Html2rss::Log).to have_received(:info).with('Test strict quality: failure_kind=quality item_count=4')
    end

    it 'does not log when strict quality passes', :aggregate_failures do
      allow(Html2rss::Log).to receive(:info)

      expect(evaluate.call(strict_quality: true).passed).to be(true)
      expect(Html2rss::Log).not_to have_received(:info)
    end
  end
end
