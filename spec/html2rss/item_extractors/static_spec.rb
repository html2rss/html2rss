# frozen_string_literal: true

RSpec.describe Html2rss::ItemExtractors::Static do
  subject { described_class.new(nil, options).get }

  let(:options) { { static: 'Foobar' } }

  it { is_expected.to eq 'Foobar' }
end
