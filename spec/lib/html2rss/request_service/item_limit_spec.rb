# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::ItemLimit do
  subject(:item_limit) { described_class.new(1) }

  let(:items) { (1..4).map { |i| "<item><title>#{i}</title><link>https://example.com/#{i}</link></item>" } }
  let(:feed) { %(<?xml version="1.0"?><rss version="2.0"><channel><title>t</title>#{items.join}) }

  describe '#reached?' do
    it 'stays false until the headroom multiple of items has closed', :aggregate_failures do
      expect(item_limit.reached?(feed.sub(items[1..].join, ''))).to be(false)
      expect(item_limit.reached?(items[1])).to be(true)
    end

    it 'scales the target with the limit', :aggregate_failures do
      three = described_class.new(3)

      expect(three.reached?(feed)).to be(false)
      expect(three.reached?(items.join)).to be(true)
    end

    it 'counts items split across chunks', :aggregate_failures do
      cut = feed.index('<link>') + 3

      expect(item_limit.reached?(feed[0, cut])).to be(false)
      expect(item_limit.reached?(feed[cut..])).to be(true)
    end

    it 'counts Atom entries with a prefix' do
      atom = '<a:feed xmlns:a="http://www.w3.org/2005/Atom"><a:entry><a:id>1</a:id></a:entry><a:entry/>'

      expect(item_limit.reached?(atom)).to be(true)
    end

    it 'gives up for good on malformed XML', :aggregate_failures do
      expect(item_limit.reached?('<rss><item></wrong></rss>')).to be(false)
      expect(item_limit.reached?(items.join * 3)).to be(false)
    end
  end

  describe '.repair' do
    it 'turns a document cut inside an item into one the syndication parser accepts', :aggregate_failures do
      repaired = described_class.repair("#{feed}<item><title>cut off")
      urls = Html2rss::Syndication::Parser.parse(repaired).articles.map { |article| article[:url].to_s }

      expect(repaired).to be_a(String)
      expect(urls).to eq((1..4).map { |i| "https://example.com/#{i}" })
    end
  end
end
