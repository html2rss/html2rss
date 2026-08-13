# frozen_string_literal: true

RSpec.describe Html2rss::SST::Node do
  describe '.build' do
    it 'requires a name' do
      expect { described_class.build(name: nil) }.to raise_error(ArgumentError)
    end

    it 'requires typed attrs' do
      expect { described_class.build(name: :div, attrs: { href: 'x' }) }.to raise_error(ArgumentError)
    end

    it 'exposes link?/heading? predicates', :aggregate_failures do
      link = described_class.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '/post'))
      junk = described_class.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '#frag'))
      heading = described_class.build(name: :h2)

      expect(link).to be_link
      expect(junk).not_to be_link
      expect(heading).to be_heading
    end

    it 'is immutable' do
      node = described_class.build(name: :div, children: [])
      expect { node.children << described_class.build(name: :span) }.to raise_error(FrozenError)
    end
  end
end
