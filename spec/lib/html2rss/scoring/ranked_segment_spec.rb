# frozen_string_literal: true

RSpec.describe Html2rss::Scoring::RankedSegment do
  let(:link) { build_node(name: :a, href: '/news/story-one', text: 'Story one') }
  let(:root) { build_node(name: :article, children: [link]) }
  let(:segment) { build_segment(root:, link:, position: 4) }
  let(:score) do
    Html2rss::Scoring::Score.new(composite: 12.5, quality: 40.0, junk: 27.5, breakdown: {})
  end
  let(:ranked) { described_class.new(segment:, score:) }

  it 'exposes the segment root and primary link', :aggregate_failures do
    expect(ranked.root_node).to be(root)
    expect(ranked.primary_link).to be(link)
  end

  it 'exposes the segment position' do
    expect(ranked.position).to eq(4)
  end

  it 'exposes the composite, quality, and junk scores', :aggregate_failures do
    expect(ranked.final_score).to eq(12.5)
    expect(ranked.quality_score).to eq(40.0)
    expect(ranked.junk_score).to eq(27.5)
  end

  it 'returns no primary link when the segment has none' do
    unlinked = described_class.new(segment: build_segment(root:, link: nil), score:)

    expect(unlinked.primary_link).to be_nil
  end
end
