# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors::PostProcessors::HtmlTransformers::TransformUrlsToAbsoluteOnes do
  subject(:transformer) { described_class.new('https://example.com/section/') }

  describe '#call' do
    subject(:call) { transformer.call(node_name: node.name, node:) }

    let(:document) do
      Nokogiri::HTML(<<~HTML)
        <html><body>
          <a href="/post">link</a>
          <img src="pic.png">
          <iframe src="/embed"></iframe>
          <p>text</p>
        </body></html>
      HTML
    end
    let(:node) { document.at(selector) }

    context 'when the node is a link' do
      let(:selector) { 'a' }

      it 'rewrites its href to an absolute url' do
        expect { call }.to change { node['href'] }.from('/post').to('https://example.com/post')
      end
    end

    context 'when the node is an image' do
      let(:selector) { 'img' }

      it 'rewrites its src against the base url' do
        expect { call }.to change { node['src'] }.from('pic.png').to('https://example.com/section/pic.png')
      end
    end

    context 'when the node is an iframe' do
      let(:selector) { 'iframe' }

      it 'rewrites its src to an absolute url' do
        expect { call }.to change { node['src'] }.from('/embed').to('https://example.com/embed')
      end
    end

    context 'when the node is not a url-bearing element' do
      let(:selector) { 'p' }

      it 'leaves the document untouched and returns nil', :aggregate_failures do
        before_html = document.to_html

        expect(call).to be_nil
        expect(document.to_html).to eq(before_html)
      end
    end
  end
end
