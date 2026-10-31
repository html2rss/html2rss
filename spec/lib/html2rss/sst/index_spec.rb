# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::SST::Index do
  let(:document) do
    Html2rss::SST::Normalizer.call(
      '<html><body><div id="w"><p>Hello <b>big</b> world</p><nav><a href="/n">Nav</a></nav></div></body></html>'
    )
  end
  let(:index) { document.index }
  let(:wrapper) { document.root.find { |node| node.attrs.id == 'w' } }
  let(:nav_link) { document.root.find { |node| node.name == :nav }.children.first }

  describe '#parent_of' do
    it 'returns the parent of a child and nil for the root', :aggregate_failures do
      expect(index.parent_of(wrapper).name).to eq(:body)
      expect(index.parent_of(document.root)).to be_nil
    end
  end

  describe '#depth_of' do
    it 'returns the depth from the root and zero for unknown nodes', :aggregate_failures do
      expect(index.depth_of(document.root)).to eq(0)
      expect(index.depth_of(wrapper)).to eq(2)
      expect(index.depth_of(Html2rss::SST::Node.build(name: :span))).to eq(0)
    end
  end

  describe '#ignored_chrome?' do
    it 'flags nodes below an ignored container and not the content beside it', :aggregate_failures do
      expect(index.ignored_chrome?(nav_link)).to be(true)
      expect(index.ignored_chrome?(wrapper)).to be(false)
      expect(index.ignored_chrome?(Html2rss::SST::Node.build(name: :span))).to be(false)
    end
  end

  describe '#descendant_of?' do
    it 'is true only for nodes strictly below the ancestor', :aggregate_failures do
      expect(index.descendant_of?(nav_link, wrapper)).to be(true)
      expect(index.descendant_of?(wrapper, wrapper)).to be(false)
      expect(index.descendant_of?(wrapper, nav_link)).to be(false)
    end
  end

  describe '#parent_until' do
    it 'returns the first node, self included, that satisfies the condition', :aggregate_failures do
      div = ->(node) { node.name == :div }

      expect(index.parent_until(nav_link, div)).to be(wrapper)
      expect(index.parent_until(wrapper, div)).to be(wrapper)
    end

    it 'returns nil when no ancestor before html satisfies the condition' do
      expect(index.parent_until(nav_link, ->(node) { node.name == :table })).to be_nil
    end

    it 'returns nil at a root that has no parent and no html element' do
      body_root = Html2rss::SST::Normalizer.call(Nokogiri::HTML('<html><body><p>x</p></body></html>').at_css('body'))
      paragraph = body_root.root.find { |node| node.name == :p }

      expect(body_root.index.parent_until(paragraph, ->(node) { node.name == :table })).to be_nil
    end

    it 'never climbs to or returns the html element', :aggregate_failures do
      html_node = ->(node) { node.name == :html }

      expect(index.parent_until(nav_link, html_node)).to be_nil
      expect(index.parent_until(document.root, html_node)).to be_nil
    end
  end

  describe '#memo_visible_text' do
    it 'returns the same visible text as the node' do
      expect(index.memo_visible_text(wrapper)).to eq("Hello big world\nNav")
    end

    it 'returns the cached text object on repeated calls' do
      first = index.memo_visible_text(wrapper)

      expect(index.memo_visible_text(wrapper)).to equal(first)
    end
  end

  describe '#memo_word_count' do
    it 'counts alphanumeric words in the visible text' do
      expect(index.memo_word_count(nav_link)).to eq(1)
    end

    it 'ignores punctuation and counts numbers as words' do
      parsed = Html2rss::SST::Normalizer.call('<html><body><p>Hello, 42 world!</p></body></html>')
      paragraph = parsed.root.find { |node| node.name == :p }

      expect(parsed.index.memo_word_count(paragraph)).to eq(3)
    end

    it 'counts zero words for a node without visible text' do
      parsed = Html2rss::SST::Normalizer.call('<html><body><p></p></body></html>')
      paragraph = parsed.root.find { |node| node.name == :p }

      expect(parsed.index.memo_word_count(paragraph)).to eq(0)
    end

    it 'returns the same count on repeated calls' do
      expect([index.memo_word_count(nav_link), index.memo_word_count(nav_link)]).to eq([1, 1])
    end
  end

  describe '#each_node' do
    it 'walks the tree depth-first starting at the root' do
      expect(index.each_node.first).to be(document.root)
    end

    it 'yields every node of the tree when given a block', :aggregate_failures do
      visited = []
      index.each_node { visited << _1 }

      expect(visited.first).to be(document.root)
      expect(visited).to include(nav_link)
      expect(visited.size).to eq(document.node_count)
    end
  end

  describe '.for_node' do
    it 'binds every node of the document to its index', :aggregate_failures do
      expect(described_class.for_node(document.root)).to be(index)
      expect(described_class.for_node(nav_link)).to be(index)
      expect(described_class.for_node(Html2rss::SST::Node.build(name: :span))).to be_nil
    end
  end
end
