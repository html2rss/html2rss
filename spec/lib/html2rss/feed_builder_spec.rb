# frozen_string_literal: true

RSpec.describe Html2rss::FeedBuilder do
  it 'is a namespace module without a build dispatcher', :aggregate_failures do
    expect(described_class).to be_a(Module)
    expect(described_class).not_to respond_to(:build)
  end
end
