# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors::PostProcessors::HtmlTransformers::WrapImgInA do
  subject(:transformer) { described_class.new }

  describe '#call' do
    subject(:call) { transformer.call(node_name: node_name, node: node) }

    let(:node_name) { 'img' }
    let(:node) { Nokogiri::HTML('<html><p><img src="https://example.com/image.jpg"></p></html>').at('img') }

    it 'wraps the image in an anchor tag', :aggregate_failures do
      expect { call }.to change { node.parent.name }.from('p').to('a')
      expect(node.parent['href']).to eq('https://example.com/image.jpg')
    end
  end
end
