# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors::Static do
  subject { described_class.new(nil, options).get }

  let(:options) { instance_double(Struct::StaticOptions, static: 'Foobar') }

  it { is_expected.to eq 'Foobar' }
end
