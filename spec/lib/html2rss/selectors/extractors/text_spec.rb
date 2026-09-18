# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors::Text do
  subject { described_class.new(xml, **options).call }

  let(:xml) { Nokogiri.HTML('<p>Lorem <b>ipsum</b> dolor ...</p>') }
  let(:options) { { selector: 'p' } }

  it { is_expected.to eq 'Lorem ipsum dolor ...' }
end
