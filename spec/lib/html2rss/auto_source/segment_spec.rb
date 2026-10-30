# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Segment do
  let(:node) { document_for('<html><body><a href="/one">One headline</a></body></html>').index.each_node.first }
  let(:subclassed_node) { Class.new(node.class).allocate }

  describe '.build' do
    it 'builds a segment carrying every field' do
      segment = described_class.build(root_node: node, primary_link: node, strategy: :list, position: 3)

      expect(segment).to have_attributes(root_node: node, primary_link: node, strategy: :list, position: 3)
    end

    it 'defaults primary_link to nil' do
      expect(described_class.build(root_node: node, strategy: :semantic, position: 0).primary_link).to be_nil
    end

    it 'accepts every allowed strategy' do
      described_class::STRATEGIES.each do |strategy|
        expect { described_class.build(root_node: node, strategy:, position: 0) }.not_to raise_error
      end
    end

    it 'accepts SST::Node subclasses for root_node and primary_link', :aggregate_failures do
      expect { described_class.build(root_node: subclassed_node, strategy: :list, position: 0) }
        .not_to raise_error
      expect { described_class.build(root_node: node, primary_link: subclassed_node, strategy: :list, position: 0) }
        .not_to raise_error
    end

    it 'rejects a non-node root_node', :aggregate_failures do
      expect { described_class.build(root_node: 'x', strategy: :list, position: 0) }
        .to raise_error(ArgumentError, 'root_node must be SST::Node')
      expect { described_class.build(root_node: nil, strategy: :list, position: 0) }
        .to raise_error(ArgumentError, 'root_node must be SST::Node')
    end

    it 'rejects a non-node primary_link', :aggregate_failures do
      expect { described_class.build(root_node: node, primary_link: 'x', strategy: :list, position: 0) }
        .to raise_error(ArgumentError, 'primary_link must be SST::Node or nil')
      expect { described_class.build(root_node: node, primary_link: true, strategy: :list, position: 0) }
        .to raise_error(ArgumentError, 'primary_link must be SST::Node or nil')
    end

    it 'rejects unknown strategies with the inspected value', :aggregate_failures do
      expect { described_class.build(root_node: node, strategy: :bogus, position: 0) }
        .to raise_error(ArgumentError, 'unknown strategy: :bogus')
      expect { described_class.build(root_node: node, strategy: nil, position: 0) }
        .to raise_error(ArgumentError, 'unknown strategy: nil')
    end

    it 'rejects a non-Integer position', :aggregate_failures do
      expect { described_class.build(root_node: node, strategy: :list, position: '1') }
        .to raise_error(ArgumentError, 'position must be Integer')
      expect { described_class.build(root_node: node, strategy: :list, position: nil) }
        .to raise_error(ArgumentError, 'position must be Integer')
    end
  end
end
