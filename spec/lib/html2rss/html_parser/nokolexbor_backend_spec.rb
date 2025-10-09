# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::HtmlParser::Backends::Nokolexbor do
  subject(:backend) { described_class.new }

  describe '#parse_html' do
    let(:html) { '<html><body><p>Example</p></body></html>' }

    it 'returns a Nokolexbor document' do
      expect(backend.parse_html(html)).to be_a(::Nokolexbor::Document)
    end
  end

  describe '#parse_html_fragment' do
    let(:html) { '<p>fragment</p>' }

    it 'returns a Nokolexbor document fragment' do
      expect(backend.parse_html_fragment(html)).to be_a(::Nokolexbor::DocumentFragment)
    end
  end

  describe '#parse_html5_fragment' do
    let(:html) { '<div><img src="/image.png"></div>' }

    it 'returns a Nokolexbor document fragment' do
      expect(backend.parse_html5_fragment(html)).to be_a(::Nokolexbor::DocumentFragment)
    end
  end

  describe '#document_class' do
    it 'returns the Nokolexbor document class' do
      expect(backend.document_class).to eq(::Nokolexbor::Document)
    end
  end

  describe '#fragment_class' do
    it 'returns the Nokolexbor fragment class' do
      expect(backend.fragment_class).to eq(::Nokolexbor::DocumentFragment)
    end
  end

  describe '#element_class' do
    it 'returns the Nokolexbor element class' do
      expect(backend.element_class).to eq(::Nokolexbor::Element)
    end
  end

  describe '#node_class' do
    it 'returns the Nokolexbor node class' do
      expect(backend.node_class).to eq(::Nokolexbor::Node)
    end
  end

  describe '#node_set_class' do
    it 'returns the Nokolexbor node set class' do
      expect(backend.node_set_class).to eq(::Nokolexbor::NodeSet)
    end
  end

  describe '#create_node' do
    let(:document) { backend.parse_html('<html></html>') }

    it 'creates an element using the backend document' do
      node = backend.create_node('span', document)

      expect(node).to be_a(::Nokolexbor::Element)
      expect(node.name).to eq('span')
    end
  end
end
