# frozen_string_literal: true

RSpec.describe Html2rss::SST::Node do
  describe '.build' do
    it 'requires a name' do
      expect { described_class.build(name: nil) }.to raise_error(ArgumentError)
    end

    it 'requires typed attrs' do
      expect { described_class.build(name: :div, attrs: { href: 'x' }) }.to raise_error(ArgumentError)
    end

    it 'exposes predicates, traversal, and leaf checks', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      link = described_class.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '/post'), own_text: 'Post')
      junk = described_class.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '#frag'))
      heading = described_class.build(name: :h2, own_text: 'Title')
      img = described_class.build(name: :img, attrs: Html2rss::SST::Attrs.build(src: '/a.png'))
      nav = described_class.build(name: :nav)
      child_div = described_class.build(name: :div, own_text: 'inner')
      parent_div = described_class.build(name: :div, children: [child_div, link])

      expect(link).to be_link
      expect(junk).not_to be_link
      expect(heading).to be_heading
      expect(img).to be_image
      expect(nav).to be_utility_landmark
      expect(nav).to be_ignored_container_name
      expect(parent_div.word_count).to be >= 1
      expect(parent_div.text_density).to be_a(Float)
      expect(parent_div.descendants).to include(link)
      expect(parent_div.find(&:link?)).to eq(link)
    end

    it 'is immutable' do
      node = described_class.build(name: :div, children: [])
      expect { node.children << described_class.build(name: :span) }.to raise_error(FrozenError)
    end
  end
end
