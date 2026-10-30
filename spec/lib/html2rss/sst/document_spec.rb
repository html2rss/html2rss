# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::SST::Document do
  let(:document) { Html2rss::SST::Normalizer.call('<html><body><p>x</p></body></html>') }
  let(:root) { document.root }
  let(:index) { document.index }

  describe '.build' do
    it 'requires a root node' do
      expect { described_class.build(root: nil, index:) }.to raise_error(ArgumentError, 'root is required')
    end

    it 'requires an index' do
      expect { described_class.build(root:, index: nil) }.to raise_error(ArgumentError, 'index is required')
    end

    it 'defaults to a non-degraded document with no nodes counted', :aggregate_failures do
      built = described_class.build(root:, index:)

      expect(built.root).to be(root)
      expect(built.index).to be(index)
      expect(built.degraded).to be(false)
      expect(built.node_count).to eq(0)
    end

    it 'coerces the degraded flag to a boolean' do
      expect(described_class.build(root:, index:, degraded: 'yes').degraded).to be(true)
    end

    it 'coerces the node count to an integer' do
      expect(described_class.build(root:, index:, node_count: '7').node_count).to eq(7)
    end
  end
end
