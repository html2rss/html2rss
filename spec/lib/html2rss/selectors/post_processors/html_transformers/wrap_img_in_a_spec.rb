# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors::PostProcessors::HtmlTransformers::WrapImgInA do
  subject(:transformer) { described_class.new }

  describe '#call' do
    subject(:call) { transformer.call(node_name:, node:) }

    let(:node_name) { 'img' }
    let(:node) { Nokogiri::HTML('<html><p><img src="https://example.com/image.jpg"></p></html>').at('img') }

    it 'wraps the image in an anchor tag', :aggregate_failures do
      expect { call }.to change { node.parent.name }.from('p').to('a')
      expect(node.parent['href']).to eq('https://example.com/image.jpg')
    end

    it 'keeps the anchor in the image original container' do
      call

      expect(node.parent.parent.name).to eq('p')
    end

    context 'when the image is already inside an anchor' do
      let(:node) { Nokogiri::HTML('<html><a href="/x"><img src="/i.png"></a></html>').at('img') }

      it 'does not wrap it a second time' do
        expect { call }.not_to(change { node.parent.parent.name })
      end
    end

    context 'when the node is not an image' do
      subject(:call) { transformer.call(node_name: 'a', node:) }

      let(:node) { Nokogiri::HTML('<html><p><a href="/x">x</a></p></html>').at('a') }

      it 'does not wrap the node' do
        expect { call }.not_to(change { node.parent.name })
      end
    end
  end
end
