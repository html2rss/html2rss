# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Config::IssueMapper do
  describe '.from' do
    it 'returns ok for a successful Dry result' do
      dry = Html2rss::Config::Validator.new.call(
        channel: { url: 'https://example.com' },
        selectors: { items: { selector: '.a' } }
      )

      expect(described_class.from(dry)).to eq(Html2rss::Config::ValidationReport.ok)
    end

    it 'maps missing keys via Dry predicate', :aggregate_failures do
      values = { channel: {}, selectors: { items: { selector: '.a' } } }
      dry = Html2rss::Config::Validator.new.call(values)
      report = described_class.from(dry, values:)

      issue = report.issues.find { |entry| entry.path == %i[channel url] }
      expect(issue.code).to eq(:missing_key)
      expect(issue.message).to eq('is missing')
    end

    it 'maps constraint predicates', :aggregate_failures do
      values = {
        channel: { url: 'https://example.com', ttl: -1 },
        selectors: { items: { selector: '.a' } }
      }
      dry = Html2rss::Config::Validator.new.call(values)
      report = described_class.from(dry, values:)

      issue = report.issues.find { |entry| entry.path == %i[channel ttl] }
      expect(issue.code).to eq(:constraint)
      expect(issue.actual).to eq(-1)
    end

    it 'strips nil base paths and defaults custom failures to invalid_value', :aggregate_failures do
      values = { channel: { url: 'https://example.com' } }
      dry = Html2rss::Config::Validator.new.call(values)
      report = described_class.from(dry, values:)

      issue = report.issues.first
      expect(issue.path).to eq([])
      expect(issue.code).to eq(:invalid_value)
    end

    it 'enriches OPTIONS-backed expected from extractor registry', :aggregate_failures do
      values = {
        channel: { url: 'https://example.com' },
        selectors: {
          items: { selector: '.a' },
          title: { selector: 'a', extractor: 'attribute' }
        }
      }
      dry = Html2rss::Config::Validator.new.call(values)
      report = described_class.from(dry, values:)

      issue = report.issues.find { |entry| entry.path == %i[selectors title attribute] }
      expect(issue.expected).to eq(type: 'string', required: true)
      expect(issue.actual).to be_nil
    end

    it 'preserves nested selector paths from the Dry result' do
      values = {
        channel: { url: 'https://example.com' },
        selectors: {
          items: { selector: '.a', pagination: { strategy: 'invalid_strategy' } }
        }
      }
      dry = Html2rss::Config::Validator.new.call(values)
      report = described_class.from(dry, values:)

      expect(report.issues.map(&:path)).to include(%i[selectors items pagination])
    end
  end

  describe '.parse_failure' do
    it 'returns a parse-coded issue' do
      report = described_class.parse_failure('boom')

      expect(report.to_h).to eq(
        success: false,
        issues: [{ path: %i[parse], code: :parse, message: 'boom', expected: nil, actual: nil }]
      )
    end
  end
end
