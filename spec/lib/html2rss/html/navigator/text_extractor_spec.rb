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
