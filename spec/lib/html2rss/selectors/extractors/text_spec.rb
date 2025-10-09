# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors::Text do
  subject { described_class.new(xml, options).get }

  let(:xml) { Html2rss::HtmlParser.parse_html('<p>Lorem <b>ipsum</b> dolor ...</p>') }
  let(:options) { instance_double(Struct::TextOptions, 'selector' => 'p') }

  it { is_expected.to eq 'Lorem ipsum dolor ...' }
end
