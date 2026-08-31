# frozen_string_literal: true

RSpec.describe Html2rss::TestResult do
  subject(:result) do
    described_class.new(
      success: true,
      item_count: 5,
      sample_items: [{ title: 'Item 1', url: 'https://example.com/1', published_at: nil }],
      channel_title: 'Example News',
      channel_url: 'https://example.com/news',
      strategy_used: :faraday,
      duration_seconds: 0.25,
      validation_errors: nil,
      error_message: nil
    )
  end

  it 'provides helper predicate methods', :aggregate_failures do
    expect(result.valid_schema?).to be(true)
    expect(result.empty_feed?).to be(false)
  end

  it 'serializes to hash cleanly' do # rubocop:disable RSpec/ExampleLength
    expect(result.to_h).to include(
      success: true,
      item_count: 5,
      channel_title: 'Example News',
      strategy_used: :faraday
    )
  end
end
