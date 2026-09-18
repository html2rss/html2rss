# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors::Static do
  subject { described_class.new(nil, **options).call }

  let(:options) { { static: 'Foobar' } }

  it { is_expected.to eq 'Foobar' }
end
