# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::SST::Text do
  let(:extract) { ->(node, **kwargs) { described_class.extract(node, **kwargs) } }

  it 'keeps direct text in document order around inline children' do
    bold = Html2rss::SST::Node.build(name: :b, own_text: 'big')
    para = Html2rss::SST::Node.build(
      name: :p, own_text: 'Hello  world', tails: [' world'], children: [bold]
    )

    expect(extract.call(para)).to eq('Hello big world')
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
    headed = Html2rss::SST::Node.build(name: :div, own_text: 'Head ', tails: [''], children: [shown])

    expect { extract.call(nil) }.to raise_error(ArgumentError, 'node is required')
    expect(extract.call(leaf)).to eq('hello world')
    expect(extract.call(blank)).to be_nil
    expect(extract.call(blocks)).to eq("One\nTwo")
    expect(extract.call(blocks, separator: ' | ')).to eq('One | Two')
    expect(extract.call(list)).to eq("- Item\n- Other")
    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: [hidden, shown]))).to eq('Shown')
    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: [fragment, link]))).to eq('Keep')
    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: [drop, stay]), exclude: [drop])).to eq('Stay')
    expect(extract.call(headed)).to eq('Head Shown')
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

  it 'keeps direct text touching an inline element in one word', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    span = ->(text) { Html2rss::SST::Node.build(name: :span, own_text: text) }
    word = Html2rss::SST::Node.build(name: :span, own_text: 'Was die n f uns', tails: ['n f', ' uns'],
                                     children: [span.call('Straßenbah'), span.call('ür')])
    spaced = Html2rss::SST::Node.build(name: :span, own_text: 'a  b', tails: [' b'], children: [span.call('x')])
    hidden = Html2rss::SST::Node.build(name: :script, own_text: 'x')
    broken = Html2rss::SST::Node.build(name: :div, children: [span.call('A'), hidden, span.call('B')])
    label = Html2rss::SST::Node.build(name: :h3, own_text: 'Headline', tails: ['Headline'],
                                      children: [span.call('Live')])

    expect(extract.call(word)).to eq('Was die Straßenbahn für uns')
    expect(extract.call(spaced)).to eq('a x b')
    expect(extract.call(Html2rss::SST::Node.build(name: :div, children: [span.call('A'), span.call('B')]))).to eq('A B')
    expect(extract.call(broken)).to eq('A B')
    expect(extract.call(label)).to eq('Live Headline')
  end

  {
    'a<b>b</b>c' => 'abc',
    'a <b>b</b> c' => 'a b c',
    'a<b>b</b> c' => 'ab c',
    'a <b>b</b>c' => 'a bc',
    'a<b>b </b>c' => 'ab c',
    'a<b> b</b>c' => 'a bc',
    'a<b><i>b</i></b>c' => 'abc',
    'a<b>x<i>b</i></b>c' => 'ax bc',
    'a<b><i>b</i>x</b>c' => 'ab xc',
    '<b>a</b>b' => 'a b',
    'a<b>b</b>' => 'a b',
    'a<b>b</b><i>c</i>d' => 'a b c d',
    'a<b>b</b><img src="/x.png">c' => 'a b c',
    'a<img src="/x.png">b' => 'a b',
    'a<b><i> x</i>y</b>c' => 'a x yc',
    '<ul><li></li><li>x</li></ul>' => '- x',
    '<ul><li><b></b></li><li>x</li></ul>' => '- x',
    'a<b>b</b><a href="#top">x</a>c' => 'a b c',
    'a<b>x<i>y</i> </b>c' => 'axy c',
    'a<b> <i>x</i>y</b>c' => 'a xyc',
    'a<b>x<i>y </i></b>c' => 'ax y c',
    'a<b><i>x</i><i>y </i></b>c' => 'ax y c',
    '<span>a<b>b</b></span>c' => 'a b c'
  }.each do |html, text|
    it "reads #{html.inspect} as #{text.inspect}" do
      node = Html2rss::SST::Normalizer.call("<html><body><h3>#{html}</h3></body></html>").root.find { _1.name == :h3 }

      expect(extract.call(node)).to eq(text)
    end
  end

  it 'reads direct text of a node built without tails' do
    bold = Html2rss::SST::Node.build(name: :b, own_text: 'big')

    expect(extract.call(Html2rss::SST::Node.build(name: :p, own_text: 'Lead', children: [bold]))).to eq('Lead big')
  end

  it 'passes the separator and exclusions down to nested children', :aggregate_failures do
    html = '<html><body><div><section><p>One</p><p>Two</p><p id="x">Drop</p></section></div></body></html>'
    root = Html2rss::SST::Normalizer.call(html).root
    div = root.find { _1.name == :div }

    expect(extract.call(div, separator: ' | ')).to eq('One | Two | Drop')
    expect(extract.call(div, exclude: [root.find { _1.attrs.id == 'x' }])).to eq("One\nTwo")
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
