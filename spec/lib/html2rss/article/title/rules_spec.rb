# frozen_string_literal: true

RSpec.describe Html2rss::Article::Title::Rules do
  describe '.build' do
    let(:markers) { Set['live blog', 'live', '独自', 'video'].freeze }
    let(:own) { Html2rss::Article::Title::OWN_CONCEPTS.to_h { [_1, ''] } }
    let(:rules) { described_class.build(markers, own) }
    let(:strip) { ->(text) { text.sub(rules.kicker_noise, '') } }

    it 'carries the marker set it was built from, and a kicker noise matcher', :aggregate_failures do
      expect(rules.markers).to be(markers)
      expect(rules.kicker_noise).to be_a(Regexp)
    end

    it 'strips a leading bracket naming one of its markers, in either bracket kind and any case',
       :aggregate_failures do
      expect(strip.call('【独自】Harbor news')).to eq('Harbor news')
      expect(strip.call('＜独自＞Harbor news')).to eq('Harbor news')
      expect(strip.call('【 Video 】Harbor news')).to eq('Harbor news')
      expect(strip.call('【LIVE BLOG】Harbor news')).to eq('Harbor news')
    end

    it 'keeps a bracket naming no marker, and a marker that is only part of the bracket', :aggregate_failures do
      expect(strip.call('【速報】Harbor news')).to eq('【速報】Harbor news')
      expect(strip.call('【独自調査】Harbor news')).to eq('【独自調査】Harbor news')
      expect(strip.call('Video Harbor news')).to eq('Video Harbor news')
    end

    it 'reads a marker that contains another marker whole', :aggregate_failures do
      expect(strip.call('【live blog】Harbor')).to eq('Harbor')
      expect(strip.call('【live】Harbor')).to eq('Harbor')
    end

    it 'strips repeated leading noise: separators, labels, separated clocks and brackets', :aggregate_failures do
      expect(strip.call(' | Section: 【独自】 10:15 - Harbor news')).to eq('Harbor news')
      expect(strip.call('19:45 Uhr | Harbor news')).to eq('Harbor news')
      expect(strip.call('Article type: Video Harbor news')).to eq('Harbor news')
    end

    it 'leaves a clock that is not set off by a separator, and text', :aggregate_failures do
      expect(strip.call('10:15 Harbor news')).to eq('10:15 Harbor news')
      expect(strip.call('Harbor news')).to eq('Harbor news')
    end

    it 'reads a type label with every marker whatever the marker set', :aggregate_failures do
      expect(described_class.build(Set['video'], own).kicker_noise.match?('記事の種類：独自')).to be(true)
    end
  end
end
