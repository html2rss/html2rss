# frozen_string_literal: true

module SstTestHelpers
  def build_node(name: :div, href: nil, class_names: nil, text: '', children: [])
    attrs = Html2rss::SST::Attrs.build(href:, class_names:)
    Html2rss::SST::Node.build(name:, attrs:, own_text: text, children:)
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

  def document_for(html)
    Html2rss::SST::Normalizer.call(html)
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/CyclomaticComplexity -- test segment fixture builder
  def segment_for(html, href: '/news/story')
    doc = Html2rss::SST::Normalizer.call(html)
    root = doc.root.find { |n| n.name == :article } || doc.root.find { |n| n.name == :div }
    link = root.find { |n| n.link? && n.attrs.href == href } || root.find(&:link?)
    Html2rss::AutoSource::Segment.build(root_node: root, primary_link: link, strategy: :semantic, position: 0)
  end
end
