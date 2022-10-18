# frozen_string_literal: true

RSpec.describe Html2rss::RssBuilder do
  it { expect(described_class).not_to respond_to(:new) }
  it { expect(described_class).to respond_to(:build) }
end
