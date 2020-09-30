# frozen_string_literal: true

RSpec.describe Html2rss::ItemExtractors::Text do
  subject { described_class.new(xml, options).get }

  let(:xml) { Nokogiri.HTML('<p>Lorem <b>ipsum</b> dolor ...</p>') }
  let(:options) { { 'selector' => 'p' } }

  it { is_expected.to eq 'Lorem ipsum dolor ...' }
end
