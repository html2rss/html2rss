# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource do
  it { expect(described_class).to be_a(Class) }

  it { expect(described_class::CHANNEL_EXTRACTORS).to be_an(Array) }
end
