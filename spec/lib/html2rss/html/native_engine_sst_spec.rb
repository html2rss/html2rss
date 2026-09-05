# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Html2rss::Html::NativeEngine SST' do
  before do
    skip 'html2rss_parser not compiled' unless Html2rss::Html::NativeEngine.available?
  end

  describe 'constants sync' do
    it 'mirrors Normalizer strip / degrade / ceiling sets', :aggregate_failures do
      expect(Html2rss::Html::NativeEngine.stripped_tags)
        .to match_array(Html2rss::SST::Normalizer::STRIPPED_TAGS.to_a)
      expect(Html2rss::Html::NativeEngine.semantic_degrade_tags)
        .to match_array(Html2rss::SST::Normalizer::SEMANTIC_DEGRADE_TAGS.to_a)
      expect(Html2rss::Html::NativeEngine.max_nodes)
        .to eq(Html2rss::SST::Normalizer::MAX_NODES)
    end
  end

  describe '.to_sst' do
    let(:fixtures) do
      {
        'simple_card' => <<~HTML,
          <html><body>
            <script>evil()</script>
            <article class="card teaser" data-id="1"><a href="/p">Post</a></article>
          </body></html>
        HTML
        'nav_chrome' => <<~HTML,
          <html><body>
            <nav><a href="/home">Home</a></nav>
            <main><h1>Title</h1><p>Hello</p></main>
          </body></html>
        HTML
        'attrs_raw' => <<~HTML
          <html><body>
            <div id="x" class="a b" category="news" data-foo="bar" onclick="nope()">
              Text
              <span itemprop="name">N</span>
            </div>
          </body></html>
        HTML
      }
    end

    it 'matches Nokogiri Normalizer structural dumps on golden fixtures', :aggregate_failures do
      fixtures.each do |name, html|
        ruby_doc = Html2rss::SST::Normalizer.call(html)
        rust_doc = Html2rss::Html::NativeEngine.to_sst(html)

        expect(dump_sst(rust_doc)).to eq(dump_sst(ruby_doc)), "fixture #{name} drifted"
      end
    end

    it 'matches Document#to_sst with string to_sst (one-parse path)', :aggregate_failures do
      fixtures.each do |name, html|
        from_string = Html2rss::Html::NativeEngine.to_sst(html)
        from_document = Html2rss::Html::NativeEngine::Document.parse(html).to_sst

        expect(dump_sst(from_document)).to eq(dump_sst(from_string)),
                                           "fixture #{name}: Document#to_sst drifted from string to_sst"
      end
    end

    it 'indexes parents the same way as the Ruby Normalizer' do
      html = fixtures.fetch('simple_card')
      rust_doc = Html2rss::Html::NativeEngine.to_sst(html)
      article = rust_doc.root.find { |n| n.name == :article }

      expect(rust_doc.index.parent_of(article.children.first)).to eq(article)
    end
  end

  def dump_sst(doc)
    {
      degraded: doc.degraded,
      node_count: doc.node_count,
      root: dump_node(doc.root)
    }
  end

  def dump_node(node)
    {
      name: node.name.to_s,
      tag_path: node.tag_path,
      # html5ever vs libxml can disagree on trailing inter-element whitespace only.
      own_text: node.own_text.rstrip,
      attrs: {
        href: node.attrs.href,
        src: node.attrs.src,
        id: node.attrs.id,
        class_names: node.attrs.class_names,
        datetime: node.attrs.datetime,
        itemprop: node.attrs.itemprop,
        style: node.attrs.style,
        srcset: node.attrs.srcset,
        type: node.attrs.type,
        raw: node.attrs.raw
      },
      children: node.children.map { |child| dump_node(child) }
    }
  end

  # Characterization lock for mend_lists libxml nest parity (BACKEND_EXPERIMENT §1).
  # Drift here means rust Path A admission no longer matches nokogiri on page_1.
  # rubocop:disable RSpec/ExampleLength -- count assertions plus backend restore
  it 'admits the same semantic/html/auto_source counts as nokogiri on page_1',
     :aggregate_failures do
    html = File.read('spec/fixtures/page_1.html')
    url = 'https://example.com/'

    nok = Html2rss::SpecSupport::Page1Admission.counts(:nokogiri, html:, url:)
    rust = Html2rss::SpecSupport::Page1Admission.counts(:rust, html:, url:)

    expect(nok).to eq([65, 61, 13]), 'nokogiri page_1 baseline drifted'
    expect(rust).to eq(nok)
  ensure
    Html2rss::Html::Backend.use(:nokogiri)
  end
  # rubocop:enable RSpec/ExampleLength
end
