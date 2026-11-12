# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Html::Navigator::TextExtractor do
  describe '.call' do
    it 'skips excluded nodes but keeps their siblings', :aggregate_failures do
      div = Nokogiri::HTML.fragment('<div><span>keep</span><span id="x">drop</span></div>').at_css('div')

      expect(described_class.call(div, exclude_nodes: [div.at_css('#x')])).to eq('keep')
      expect(described_class.call(div, exclude_nodes: [])).to eq('keep drop')
      expect(described_class.call(div)).to eq('keep drop')
    end

    it 'joins nested block children with the given separator', :aggregate_failures do
      div = Nokogiri::HTML.fragment('<div><div><p>a</p><p>b</p></div></div>').at_css('div')

      expect(described_class.call(div, separator: '|')).to eq('a|b')
      expect(described_class.call(div)).to eq("a\nb")
    end

    it 'separates text of nested inline and block elements', :aggregate_failures do
      div = Nokogiri::HTML.fragment('<div>x<div>a<p>b</p></div>c</div>').at_css('div')

      expect(described_class.call(div)).to eq("x\na\nb\nc")
    end

    it 'keeps direct text touching an inline element in one word', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      word = Nokogiri::HTML.fragment('<h3>Was die <span>Straßenbah</span>n <b>f</b>ür <i>uns</i></h3>').at_css('h3')
      label = Nokogiri::HTML.fragment('<h3><span>Live</span>Headline</h3>').at_css('h3')
      spans = Nokogiri::HTML.fragment('<h3><span>Kicker</span><span>Headline</span></h3>').at_css('h3')
      spaced = Nokogiri::HTML.fragment('<h3>a <span>x</span> b</h3>').at_css('h3')
      broken = Nokogiri::HTML.fragment('<h3>A<script>x</script><span>B</span></h3>').at_css('h3')

      expect(described_class.call(word)).to eq('Was die Straßenbahn für uns')
      expect(described_class.call(label)).to eq('Live Headline')
      expect(described_class.call(spans)).to eq('Kicker Headline')
      expect(described_class.call(spaced)).to eq('a x b')
      expect(described_class.call(broken)).to eq('A B')
    end

    {
      'a<b>b</b>c' => 'abc',
      'a <b>b</b> c' => 'a b c',
      'a<b>b</b> c' => 'ab c',
      'a <b>b</b>c' => 'a bc',
      'a<b>b </b>c' => 'ab c',
      'a<b> b</b>c' => 'a bc',
      'a<b><i>b</i></b>c' => 'abc',
      '<b>a</b>b' => 'a b',
      'a<b>b</b>' => 'a b',
      '<b>a</b>b<i>c</i>' => 'a b c',
      'a<b>b</b><i>c</i>d' => 'a b c d',
      'a<b>b</b><script>x</script>c' => 'a b c',
      'a<b>b</b><i> </i>c' => 'a b c'
    }.each do |html, text|
      it "reads #{html} as #{text.inspect}" do
        expect(described_class.call(Nokogiri::HTML.fragment("<h3>#{html}</h3>").at_css('h3'))).to eq(text)
      end
    end

    it 'keeps a block break across a hidden piece', :aggregate_failures do
      div = Nokogiri::HTML.fragment('<div><p>One</p><script>x</script>Two</div>').at_css('div')

      expect(described_class.call(div)).to eq("One\nTwo")
      expect(described_class.call(div, separator: '|')).to eq('One|Two')
    end

    it 'prefixes list items with a dash' do
      ul = Nokogiri::HTML.fragment('<ul><li>one</li><li>two</li></ul>').at_css('ul')

      expect(described_class.call(ul)).to eq("- one\n- two")
    end

    it 'returns nil when the tag has no visible text' do
      div = Nokogiri::HTML.fragment('<div>   <script>x()</script></div>').at_css('div')

      expect(described_class.call(div)).to be_nil
    end

    it 'drops script, style, svg, template and noscript content', :aggregate_failures do
      div = Nokogiri::HTML.fragment(
        '<div>a<script>s()</script>b<style>p{}</style>c<svg><text>v</text></svg>' \
        'd<template>t</template><noscript>n</noscript>e</div>'
      ).at_css('div')

      expect(described_class.call(div)).to eq('a b c d e')
    end

    it 'drops same-page anchors but keeps other links', :aggregate_failures do
      div = Nokogiri::HTML.fragment('<div>Read <a href="#top">top</a> and <a href="/x">news</a> <a>plain</a></div>')
                          .at_css('div')

      expect(described_class.call(div)).to eq('Read and news plain')
    end

    it 'applies exclusions inside nested elements' do
      div = Nokogiri::HTML.fragment('<div><p><span id="x">drop</span>keep</p></div>').at_css('div')

      expect(described_class.call(div, exclude_nodes: [div.at_css('#x')])).to eq('keep')
    end

    it 'collapses whitespace inside a leaf element', :aggregate_failures do
      div = Nokogiri::HTML.fragment("<div><span>Hello   World</span><span>a\n\nb</span></div>").at_css('div')

      expect(described_class.call(div)).to eq('Hello World a b')
    end

    it 'treats empty elements and whitespace-only blocks as no text', :aggregate_failures do
      expect(described_class.call(Nokogiri::HTML.fragment('<div>a<br>b</div>').at_css('div'))).to eq('a b')
      expect(described_class.call(Nokogiri::HTML.fragment('<div>a<p> </p>b</div>').at_css('div'))).to eq('a b')
    end

    it 'joins a text node without separator handling' do
      text_node = Nokogiri::HTML.fragment('  Hello   World  ').children.first

      expect(described_class.call(text_node, separator: '|')).to eq('Hello World')
    end
  end
end
