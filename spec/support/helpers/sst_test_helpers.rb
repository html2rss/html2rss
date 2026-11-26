# frozen_string_literal: true

module SstTestHelpers
  # The scope of a page whose language is unknown: every shared term applies.
  def all_scope = Html2rss::Vocabulary[:all]

  def build_node(name: :div, href: nil, class_names: nil, text: '', children: [])
    attrs = Html2rss::Html::SST::Attrs.build(href:, class_names:)
    Html2rss::Html::SST::Node.build(name:, attrs:, own_text: text, children:)
  end

  def build_segment(root:, link: nil, position: 0)
    Html2rss::AutoSource::Segment.build(
      root_node: root,
      primary_link: link,
      strategy: :semantic,
      position:
    )
  end

  def article_segment(href:, title:, position:)
    link = build_node(name: :a, href:, text: title)
    root = build_node(
      name: :article,
      children: [
        build_node(name: :h2, text: title),
        link,
        build_node(name: :p, text: 'Extra descriptive context that is long enough for signals here.')
      ]
    )
    build_segment(root:, link:, position:)
  end

  def usable_card?(node) = Html2rss::Html::Navigator.usable_card_parent?(node, vocabulary: all_scope)

  # The page's link resolver, as AutoSource builds it once per page.
  def page_resolver(base_url = 'https://example.com', vocabulary: Html2rss::Vocabulary[nil])
    Html2rss::Scoring::LinkResolver.new(base_url, vocabulary:)
  end

  # The fields of the +item+ (CSS selector) in +html+, read the way +selectors.items.enhance+ reads a selected item:
  # its first link is the primary one. The SST document is held until the fields are read.
  def item_fields_for(html, item: 'article', nth: 0, base_url: 'https://example.com', time_zone: 'UTC', # rubocop:disable Metrics/ParameterLists
                      vocabulary: all_scope)
    parsed = Nokogiri::HTML(html)
    document = Html2rss::Html::SST::Normalizer.call(parsed, vocabulary:, items: true)
    root = document.index.node_for(parsed.css(item)[nth])
    segment = Html2rss::AutoSource::Segment.build(root_node: root, primary_link: root.find(&:link?),
                                                  strategy: :list, position: 0)
    resolver = page_resolver(base_url, vocabulary:)
    [Html2rss::AutoSource::ArticleExtractor::Item.call(segment, base_url:, time_zone:, link_resolver: resolver),
     document].first
  end

  # A node of a document nothing references any more, so its index is free to be collected.
  def orphan_node_for(html) = document_for(html).root.find(&:link?)

  # A segment of +html+ whose document nothing references, so its index is free to be collected.
  def build_orphan_segment(html)
    root = document_for(html).root.find { _1.name == :article }
    Html2rss::AutoSource::Segment.build(root_node: root, primary_link: root.find(&:link?), strategy: :semantic,
                                        position: 0)
  end

  # Keeps +doc+ referenced for the example so its index stays live; returns +doc+.
  def hold_document(doc) = doc.tap { (@sst_documents ||= []) << _1 }

  def document_for(html)
    Html2rss::Html::SST::Normalizer.call(html, vocabulary: all_scope)
  end

  # The segment's SST document is held by the example, as production holds it, so its index stays live.
  # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity -- test segment fixture builder
  def segment_for(html, href: '/news/story')
    doc = Html2rss::Html::SST::Normalizer.call(html, vocabulary: all_scope)
    hold_document(doc)
    root = doc.root.find { |n| n.name == :article } || doc.root.find { |n| n.name == :div }
    link = root.find { |n| n.link? && n.attrs.href == href } || root.find(&:link?)
    Html2rss::AutoSource::Segment.build(root_node: root, primary_link: link, strategy: :semantic, position: 0)
  end
end
