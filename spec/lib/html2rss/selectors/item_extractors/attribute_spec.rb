# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::ItemExtractors::Attribute do
  subject { described_class.new(xml, options).get }

  let(:xml) { Nokogiri.HTML('<div><time datetime="2019-07-01">...</time></div>') }
  let(:options) { instance_double(Struct::AttributeOptions, selector: 'time', attribute: 'datetime') }

  it { is_expected.to eq '2019-07-01' }
end
