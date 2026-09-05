# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::SST::Hydrator do
  describe '.call' do
    subject(:document) { described_class.call(root_ir, node_count: 5, degraded: false) }

    let(:root_ir) do
      {
        'name' => 'html',
        'attrs' => { 'class_names' => [], 'raw' => {} },
        'own_text' => '',
        'tag_path' => '/html',
        'depth' => 0,
        'chrome' => false,
        'children' => [
          {
            'name' => 'body',
            'attrs' => { 'class_names' => [], 'raw' => {} },
            'own_text' => '',
            'tag_path' => '/html/body',
            'depth' => 1,
            'chrome' => false,
            'children' => [
              {
                'name' => 'nav',
                'attrs' => { 'class_names' => [], 'raw' => {} },
                'own_text' => '',
                'tag_path' => '/html/body/nav',
                'depth' => 2,
                'chrome' => true,
                'children' => []
              },
              {
                'name' => 'article',
                'attrs' => {
                  'href' => nil,
                  'class_names' => %w[card],
                  'raw' => { 'data-id' => '1' }
                },
                'own_text' => '',
                'tag_path' => '/html/body/article',
                'depth' => 2,
                'chrome' => false,
                'children' => [
                  {
                    'name' => 'a',
                    'attrs' => { 'href' => '/p', 'class_names' => [], 'raw' => {} },
                    'own_text' => 'Post',
                    'tag_path' => '/html/body/article/a',
                    'depth' => 3,
                    'chrome' => false,
                    'children' => []
                  }
                ]
              }
            ]
          }
        ]
      }
    end

    it 'builds Document with Attrs/Node/Index invariants', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      expect(document).to be_a(Html2rss::SST::Document)
      expect(document.node_count).to eq(5)
      expect(document.degraded).to be(false)
      expect(document.root.name).to eq(:html)

      article = document.root.find { |n| n.name == :article }
      expect(article.attrs.class_names).to eq(%w[card])
      expect(article.attrs.raw).to eq('data-id' => '1')
      expect(document.index.parent_of(article.children.first)).to eq(article)
      expect(document.index.depth_of(article)).to eq(2)
      expect(document.index.ignored_chrome?(article)).to be(false)

      nav = document.root.find { |n| n.name == :nav }
      expect(document.index.ignored_chrome?(nav)).to be(true)
    end

    it 'accepts symbol keys in the IR', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      symbolic = {
        name: 'div',
        attrs: { class_names: %w[x], raw: {} },
        own_text: 'hi',
        tag_path: '/div',
        depth: 0,
        chrome: false,
        children: []
      }

      doc = described_class.call(symbolic, node_count: 1, degraded: true)
      expect(doc.root.name).to eq(:div)
      expect(doc.root.own_text).to eq('hi')
      expect(doc.degraded).to be(true)
    end
  end
end
