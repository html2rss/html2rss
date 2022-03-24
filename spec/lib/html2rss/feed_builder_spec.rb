# frozen_string_literal: true

RSpec.describe Html2rss::FeedBuilder do
  it { expect(described_class).not_to respond_to(:new) }
  it { expect(described_class).to respond_to(:build) }
end
