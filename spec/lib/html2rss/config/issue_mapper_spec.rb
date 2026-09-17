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
      report = described_class.from(Html2rss::Config::Validator.new.call(values), values:)
      issue = report.issues.find { |entry| entry.path == %i[channel url] }

      expect(issue.code).to eq(:missing_key)
      expect(issue.message).to eq('is missing')
    end

    it 'maps constraint predicates', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      values = {
        channel: { url: 'https://example.com', ttl: -1 },
        selectors: { items: { selector: '.a' } }
      }
      report = described_class.from(Html2rss::Config::Validator.new.call(values), values:)
      issue = report.issues.find { |entry| entry.path == %i[channel ttl] }

      expect(issue.code).to eq(:constraint)
      expect(issue.actual).to eq(-1)
    end

    it 'strips nil base paths and defaults custom failures to invalid_value', :aggregate_failures do
      values = { channel: { url: 'https://example.com' } }
      report = described_class.from(Html2rss::Config::Validator.new.call(values), values:)

      expect(report.issues.first.path).to eq([])
      expect(report.issues.first.code).to eq(:invalid_value)
    end

    it 'enriches OPTIONS-backed expected from extractor registry', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      values = {
        channel: { url: 'https://example.com' },
        selectors: { items: { selector: '.a' }, title: { selector: 'a', extractor: 'attribute' } }
      }
      report = described_class.from(Html2rss::Config::Validator.new.call(values), values:)
      issue = report.issues.find { |entry| entry.path == %i[selectors title attribute] }

      expect(issue.expected).to eq(type: 'string', required: true)
      expect(issue.actual).to be_nil
    end

    it 'preserves nested selector paths from the Dry result' do # rubocop:disable RSpec/ExampleLength
      values = {
        channel: { url: 'https://example.com' },
        selectors: { items: { selector: '.a', pagination: { strategy: 'invalid_strategy' } } }
      }
      report = described_class.from(Html2rss::Config::Validator.new.call(values), values:)

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

  describe 'PREDICATE_CODES coverage' do
    # Invalid configs that together exercise Dry predicates from Validator / SelectorsValidator.
    COVERAGE_VALUES = [
      { channel: {}, selectors: { items: { selector: '.a' } } },
      { channel: { url: '' }, selectors: { items: { selector: '.a' } } },
      { channel: { url: 'https://example.com', ttl: 'x' }, selectors: { items: { selector: '.a' } } },
      { channel: { url: 'https://example.com', ttl: -1 }, selectors: { items: { selector: '.a' } } },
      { channel: { url: 'https://example.com', language: 'ENGLISH' }, selectors: { items: { selector: '.a' } } },
      {
        channel: { url: 'https://example.com' },
        selectors: { items: { selector: '.a', enhance: 'yes' } }
      },
      {
        channel: { url: 'https://example.com' },
        directory: { title: 'T', topics: ['not-a-topic'] },
        selectors: { items: { selector: '.a' } }
      },
      {
        channel: { url: 'https://example.com' },
        directory: { title: 'T', topics: [] },
        selectors: { items: { selector: '.a' } }
      },
      {
        channel: { url: 'https://example.com' },
        directory: { title: 'T', summary: 'x' * 161 },
        selectors: { items: { selector: '.a' } }
      },
      {
        channel: { url: 'https://example.com' },
        request: { max_redirects: -1 },
        selectors: { items: { selector: '.a' } }
      },
      {
        channel: { url: 'https://example.com' },
        request: {
          botasaurus: { max_retries: Html2rss::RequestService::BotasaurusContract::MAX_RETRIES + 1 }
        },
        selectors: { items: { selector: '.a' } }
      },
      {
        channel: { url: 'https://example.com' },
        stylesheets: [{ href: '/x.css', type: 'text/unknown' }],
        selectors: { items: { selector: '.a' } }
      },
      {
        channel: { url: 'https://example.com' },
        selectors: { items: { selector: '.a' }, enclosure: { selector: 'a', content_type: 'audio' } }
      }
    ].freeze

    it 'maps every Dry predicate emitted by Validator / SelectorsValidator', :aggregate_failures do
      seen = Set.new

      COVERAGE_VALUES.each do |values|
        dry = Html2rss::Config::Validator.new.call(values)
        next if dry.success?

        dry.errors.each do |message|
          predicate = message.predicate
          next if predicate.nil?

          expect(described_class::PREDICATE_CODES).to have_key(predicate),
                                                      "unmapped predicate #{predicate.inspect} path=#{message.path}"
          seen << predicate
          described_class.from(dry, values:) # raises if unmapped
        end
      end

      expect(seen).not_to be_empty
    end

    it 'rejects unknown predicates loudly' do
      message = instance_double(
        Dry::Schema::Message,
        path: %i[channel url],
        predicate: :never_heard_of?,
        text: 'weird',
        input: nil
      )
      dry = instance_double(Dry::Validation::Result, success?: false, errors: [message])

      expect { described_class.from(dry, values: {}) }
        .to raise_error(ArgumentError, /unmapped Dry validation predicate: :never_heard_of\?/)
    end
  end
end
