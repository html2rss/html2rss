# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Config::ValidationReport do
  describe '.ok' do
    subject(:report) { described_class.ok }

    it 'is a successful empty report', :aggregate_failures do
      expect(report).to be_success
      expect(report).not_to be_failure
      expect(report.issues).to eq([])
      expect(report.to_h).to eq(success: true, issues: [])
    end
  end

  describe '.failure' do
    subject(:report) do
      described_class.failure(
        [
          Html2rss::Config::ValidationIssue.new(
            path: %i[channel url],
            code: :missing_key,
            message: 'is missing'
          )
        ]
      )
    end

    it 'serializes issues only', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      expect(report).to be_failure
      expect(report.to_h).to eq(
        success: false,
        issues: [
          {
            path: %i[channel url],
            code: :missing_key,
            message: 'is missing',
            expected: nil,
            actual: nil
          }
        ]
      )
    end
  end
end
