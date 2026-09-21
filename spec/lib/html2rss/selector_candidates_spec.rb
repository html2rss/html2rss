# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::SelectorCandidates do
  describe '.empty' do
    it 'returns frozen empty buckets for all keys', :aggregate_failures do
      expect(described_class.empty).to eq(items: [], title: [], link: [], published: [])
      expect(described_class.empty).to be_frozen
    end
  end

  describe '.call' do
    it 'returns EMPTY when items evidence is blank' do
      expect(described_class.call(items_evidence: [])).to eq(described_class.empty)
    end

    it 'ranks items best-first and deduplicates selectors', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      empty = Html2rss::SST::Attrs.empty
      root = Html2rss::SST::Node.build(name: :div, attrs: empty, tag_path: '/html/body/div')
      evidence = [
        { selector: 'main > div', enhance: true, strategy: :list, kind: :path, match_count: 3,
          roots: [root, root] },
        { selector: 'div.item', enhance: true, strategy: :cluster, kind: :shared_class, match_count: 2,
          roots: [root, root] },
        { selector: 'div.item', enhance: true, strategy: :list, kind: :shared_class, match_count: 3,
          roots: [root, root] },
        { selector: 'article, section', enhance: true, strategy: :list, kind: :unique_tag, match_count: 4,
          roots: [root, root] }
      ]

      items = described_class.call(items_evidence: evidence)[:items]
      expect(items.map { |c| c[:selector] }).to eq(['div.item', 'article, section', 'main > div'])
      expect(items.first).to eq(selector: 'div.item', enhance: true)
    end

    # rubocop:disable-next RSpec/ExampleLength -- field bucket contract across three keys
    it 'derives repeated relative title, link, and published selectors', :aggregate_failures do
      roots = Array.new(2) do |index|
        href = "/post-#{index + 1}"
        link = Html2rss::SST::Node.build(
          name: :a, attrs: Html2rss::SST::Attrs.build(href:), own_text: "Post #{index}",
          tag_path: '/html/body/div/h2/a'
        )
        heading = Html2rss::SST::Node.build(
          name: :h2, attrs: Html2rss::SST::Attrs.empty, children: [link], tag_path: '/html/body/div/h2'
        )
        time = Html2rss::SST::Node.build(
          name: :time, attrs: Html2rss::SST::Attrs.build(datetime: "2024-01-0#{index + 1}"),
          own_text: 'Jan', tag_path: '/html/body/div/time'
        )
        Html2rss::SST::Node.build(
          name: :div, attrs: Html2rss::SST::Attrs.build(class_names: ['item']),
          children: [heading, time], tag_path: '/html/body/div'
        )
      end
      evidence = [
        { selector: 'div.item', enhance: true, strategy: :list, kind: :shared_class, match_count: 2, roots: }
      ]

      buckets = described_class.call(items_evidence: evidence)
      expect(buckets[:title]).to eq([{ selector: 'h2' }])
      expect(buckets[:link]).to eq([{ selector: 'h2 > a' }])
      expect(buckets[:published]).to eq([{ selector: 'time' }])
    end

    # rubocop:disable-next RSpec/ExampleLength -- min_matches gate for published vs title
    it 'omits field selectors that appear on fewer than min_matches roots', :aggregate_failures do
      with_time = begin
        link = Html2rss::SST::Node.build(
          name: :a, attrs: Html2rss::SST::Attrs.build(href: '/1'), own_text: 'One',
          tag_path: '/html/body/div/h2/a'
        )
        heading = Html2rss::SST::Node.build(
          name: :h2, attrs: Html2rss::SST::Attrs.empty, children: [link], tag_path: '/html/body/div/h2'
        )
        time = Html2rss::SST::Node.build(
          name: :time, attrs: Html2rss::SST::Attrs.build(datetime: '2024-01-01'),
          own_text: 'Jan', tag_path: '/html/body/div/time'
        )
        Html2rss::SST::Node.build(
          name: :div, attrs: Html2rss::SST::Attrs.build(class_names: ['item']),
          children: [heading, time], tag_path: '/html/body/div'
        )
      end
      without_time = begin
        link = Html2rss::SST::Node.build(
          name: :a, attrs: Html2rss::SST::Attrs.build(href: '/2'), own_text: 'Two',
          tag_path: '/html/body/div/h2/a'
        )
        heading = Html2rss::SST::Node.build(
          name: :h2, attrs: Html2rss::SST::Attrs.empty, children: [link], tag_path: '/html/body/div/h2'
        )
        Html2rss::SST::Node.build(
          name: :div, attrs: Html2rss::SST::Attrs.build(class_names: ['item']),
          children: [heading], tag_path: '/html/body/div'
        )
      end
      evidence = [
        { selector: 'div.item', enhance: true, strategy: :list, kind: :shared_class, match_count: 2,
          roots: [with_time, without_time] }
      ]

      buckets = described_class.call(items_evidence: evidence)
      expect(buckets[:published]).to eq([])
      expect(buckets[:title]).to eq([{ selector: 'h2' }])
    end

    # rubocop:disable-next RSpec/ExampleLength -- wrapping-anchor roots skip link bucket
    it 'skips link candidates when the item root is itself a link', :aggregate_failures do
      roots = %w[/news/one /news/two].map do |href|
        Html2rss::SST::Node.build(
          name: :a,
          attrs: Html2rss::SST::Attrs.build(href:),
          children: [
            Html2rss::SST::Node.build(
              name: :h2, attrs: Html2rss::SST::Attrs.empty, own_text: href,
              tag_path: '/html/body/a/h2'
            )
          ],
          tag_path: '/html/body/a'
        )
      end
      evidence = [
        { selector: 'a', enhance: true, strategy: :list, kind: :path, match_count: 2, roots: }
      ]

      buckets = described_class.call(items_evidence: evidence)
      expect(buckets[:link]).to eq([])
      expect(buckets[:title]).to eq([{ selector: 'h2' }])
    end
  end
end
