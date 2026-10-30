# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::SST::Text do
  let(:extract) { ->(node, **kwargs) { described_class.extract(node, **kwargs) } }

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

  it 'joins nested inline children with a single space', :aggregate_failures do
    inline = ->(text) { Html2rss::SST::Node.build(name: :span, own_text: text) }
    nested = Html2rss::SST::Node.build(name: :span, children: [inline.call('a'), inline.call('b')])

    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: [nested]))).to eq('a b')
  end

  it 'separates block children with the separator and inline children with a space', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    paragraphs = [Html2rss::SST::Node.build(name: :p, own_text: 'one'),
                  Html2rss::SST::Node.build(name: :p, own_text: 'two')]
    spans = [Html2rss::SST::Node.build(name: :span, own_text: 'one'),
             Html2rss::SST::Node.build(name: :span, own_text: 'two')]

    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: paragraphs),
                        separator: ' | ')).to eq('one | two')
    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: spans), separator: ' | ')).to eq('one two')
  end

  it 'separates a block from a neighbouring inline child with a newline', :aggregate_failures do
    inline = Html2rss::SST::Node.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '/a'), own_text: 'a')
    block = Html2rss::SST::Node.build(name: :p, own_text: 'b')

    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: [inline, block]))).to eq("a\nb")
    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: [block, inline]))).to eq("b\na")
  end

  it 'prefixes list items with a dash' do
    item = Html2rss::SST::Node.build(name: :li, children: [Html2rss::SST::Node.build(name: :span, own_text: 'A')])
    other = Html2rss::SST::Node.build(name: :li, own_text: 'B')

    expect(extract.call(Html2rss::SST::Node.build(name: :ul, children: [item, other]))).to eq("- A\n- B")
  end

  it 'hides fragment links and svg graphics from the visible text', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    top = Html2rss::SST::Node.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '#top'), own_text: 'x')
    link = Html2rss::SST::Node.build(name: :a, attrs: Html2rss::SST::Attrs.build(href: '/p'), own_text: 'y')
    graphic = Html2rss::SST::Node.build(name: :svg, own_text: 'g')
    label = Html2rss::SST::Node.build(name: :span, own_text: 'k')

    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: [top, link]))).to eq('y')
    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: [graphic, label]))).to eq('k')
  end

  it 'trims own text' do
    node = Html2rss::SST::Node.build(name: :div, own_text: '  lead  ', children: [])

    expect(extract.call(node)).to eq('lead')
  end
end
