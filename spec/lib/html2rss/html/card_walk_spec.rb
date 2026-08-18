# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Html::CardWalk do
  describe '.miss?' do
    it 'climbs only heading/anchor items that lack leftover description and date', :aggregate_failures do
      expect(described_class.miss?(heading_or_anchor_item: true, published_at: nil, description: nil)).to be true
      expect(described_class.miss?(heading_or_anchor_item: true, published_at: nil,
                                   description: 'A real teaser.')).to be false
      expect(described_class.miss?(heading_or_anchor_item: false, published_at: nil, description: nil)).to be false
    end
  end

  describe '.thin_wrapper?' do
    let(:item) { Object.new }

    it 'is thin when the only child is the item itself' do
      expect(described_class.thin_wrapper?(children: [item], item:, descendant_of: ->(*) { false })).to be true
    end

    it 'is thin when the only child wraps the item' do
      inner = Object.new
      descendant_of = ->(candidate, child) { candidate.equal?(item) && child.equal?(inner) }
      expect(described_class.thin_wrapper?(children: [inner], item:, descendant_of:)).to be true
    end

    it 'is not thin when a sibling sits beside the item' do
      sibling = Object.new
      expect(
        described_class.thin_wrapper?(children: [item, sibling], item:, descendant_of: ->(*) { false })
      ).to be false
    end
  end

  describe '.crowded?' do
    it 'aborts when a parent has two headings or two distinct main hrefs', :aggregate_failures do
      expect(described_class.crowded?(heading_count: 2, distinct_main_hrefs: 1)).to be true
      expect(described_class.crowded?(heading_count: 1, distinct_main_hrefs: 2)).to be true
      expect(described_class.crowded?(heading_count: 1, distinct_main_hrefs: 1)).to be false
    end
  end
end
