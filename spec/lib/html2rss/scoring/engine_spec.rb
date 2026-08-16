# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Scoring::Engine do
  def build_node(name:, href: nil, text: '', children: [])
    attrs = Html2rss::SST::Attrs.build(href:)
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

  let(:engine) { described_class.new(link_resolver: Html2rss::Scoring::LinkResolver.new('https://example.com/')) }

  describe '#rank / #rank_top' do
    let(:segments) do
      junk_link = build_node(name: :a, href: '/login', text: 'Login')
      [
        build_segment(root: build_node(name: :div, children: [junk_link]), link: junk_link, position: 0),
        article_segment(href: '/news/deep-story-slug-here', title: 'Deep Story Title Words', position: 1)
      ]
    end

    it 'drops hard-junk destinations and ranks content above chrome', :aggregate_failures do
      ranked = engine.rank(segments)
      expect(ranked.map { _1.primary_link.attrs.href }).to eq(['/news/deep-story-slug-here'])
      expect(ranked.first.final_score).to be > described_class::SCORE_FLOOR
    end

    it 'applies the score floor in rank_top', :aggregate_failures do
      top = engine.rank_top(segments, limit: 10)
      expect(top.size).to eq(1)
      expect(top.first.final_score).to be >= described_class::SCORE_FLOOR
    end

    it 'demotes commerce affiliate paths via utility_path without title word lists' do
      affiliate = article_segment(href: '/dating/singles-in-berlin', title: 'Singles in Berlin finden', position: 0)
      news = article_segment(href: '/news/deep-story-slug-here', title: 'Deep Story Title Words', position: 1)
      expect(engine.rank([affiliate, news]).map { _1.primary_link.attrs.href }).to eq(['/news/deep-story-slug-here'])
    end
  end

  describe '#select_eligible' do
    let(:segments) do
      first_link = build_node(name: :a, href: '/posts/one-two-three', text: 'First Card Title')
      second_link = build_node(name: :a, href: '/posts/four-five-six', text: 'Second Card Title')
      [
        build_segment(root: build_node(name: :li, children: [first_link]), link: first_link, position: 2),
        build_segment(root: build_node(name: :li, children: [second_link]), link: second_link, position: 1)
      ]
    end

    it 'preserves discovery position order after eligibility', :aggregate_failures do
      eligible = engine.select_eligible(segments, limit: 10)
      expect(eligible.map(&:position)).to eq([1, 2])
      expect(eligible.map { _1.primary_link.attrs.href }).to eq(
        ['/posts/four-five-six', '/posts/one-two-three']
      )
    end
  end
end
