# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::UnsupportedUrlScheme do
  it 'carries the retry URL as a string diagnostic', :aggregate_failures do
    error = described_class.new('downgraded', retry_url: Html2rss::Url.from_absolute('https://example.com/a'))

    expect(error.message).to eq('downgraded')
    expect(error.retry_url).to eq('https://example.com/a')
    expect(error.diagnostics).to eq(retry_url: 'https://example.com/a')
  end

  it 'keeps the attempt diagnostics every Html2rss::Error carries' do
    error = described_class.new('downgraded', retry_url: 'https://example.com/a')
    error.attempts = [{ strategy: :default }]

    expect(error.diagnostics).to eq(strategy_attempts: [{ strategy: :default }], retry_url: 'https://example.com/a')
  end

  it 'has no retry URL and no diagnostics by default', :aggregate_failures do
    error = described_class.new('bad scheme')

    expect(error.retry_url).to be_nil
    expect(error.diagnostics).to eq({})
    expect(error.kind).to eq(:invalid_url)
  end
end
