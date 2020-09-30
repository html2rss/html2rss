# frozen_string_literal: true

RSpec.describe Html2rss::ItemExtractors::CurrentTime do
  subject { described_class.new(nil, nil).get }

  it { is_expected.to be_a(Time) }
end
