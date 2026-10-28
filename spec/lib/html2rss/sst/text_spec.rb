# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::SST::Text do
  let(:extract) do
    lambda do |node, **kwargs|
      Object.new.extend(described_class).instance_eval { extract(node, **kwargs) }
    end
  end

  it 'collapses whitespace, skips chrome, and separates blocks', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    leaf = Html2rss::SST::Node.build(name: :span, own_text: "  hello   world \n ")
    blank = Html2rss::SST::Node.build(name: :span, own_text: '   ')
    one = Html2rss::SST::Node.build(name: :p, own_text: 'One')
    two = Html2rss::SST::Node.build(name: :p, own_text: 'Two')
    blocks = Html2rss::SST::Node.build(name: :div, children: [one, two])
    item = Html2rss::SST::Node.build(name: :li, own_text: 'Item')
    other = Html2rss::SST::Node.build(name: :li, own_text: 'Other')
    list = Html2rss::SST::Node.build(name: :ul, children: [item, other])
    hidden = Html2rss::SST::Node.build(name: :script, own_text: 'evil')
    shown = Html2rss::SST::Node.build(name: :span, own_text: 'Shown')
    fragment = Html2rss::SST::Node.build(
      name: :a, attrs: Html2rss::SST::Attrs.build(href: '#top'), own_text: 'Skip'
    )
    link = Html2rss::SST::Node.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '/p'), own_text: 'Keep')
    drop = Html2rss::SST::Node.build(name: :span, own_text: 'Drop')
    stay = Html2rss::SST::Node.build(name: :span, own_text: 'Stay')
    headed = Html2rss::SST::Node.build(name: :div, own_text: 'Head', children: [shown])

    expect { extract.call(nil) }.to raise_error(ArgumentError, 'node is required')
    expect(extract.call(leaf)).to eq('hello world')
    expect(extract.call(blank)).to be_nil
    expect(extract.call(blocks)).to eq("One\nTwo")
    expect(extract.call(blocks, separator: ' | ')).to eq('One | Two')
    expect(extract.call(list)).to eq("- Item\n- Other")
    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: [hidden, shown]))).to eq('Shown')
    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: [fragment, link]))).to eq('Keep')
    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: [drop, stay]), exclude: [drop])).to eq('Stay')
    expect(extract.call(headed)).to eq('HeadShown')
  end
end
