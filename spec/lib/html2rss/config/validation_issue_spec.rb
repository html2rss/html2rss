# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Config::ValidationIssue do
  it 'builds an issue for a known code' do
    issue = described_class.new(path: %i[channel], code: :missing_key, message: 'is missing')

    expect(issue.code).to eq(:missing_key)
  end

  it 'raises its owner InvalidError (a ContractError) for an unknown code' do
    expect { described_class.new(path: [], code: :bogus, message: 'x') }
      .to raise_error(described_class::InvalidError, 'unknown ValidationIssue code: :bogus')
  end
end
