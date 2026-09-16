# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors::Static do
  subject { described_class.new(nil, options).get }

  let(:options) { described_class::Options.new(static: 'Foobar') }

  it { is_expected.to eq 'Foobar' }
end
