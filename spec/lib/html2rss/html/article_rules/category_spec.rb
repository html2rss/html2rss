# frozen_string_literal: true

RSpec.describe Html2rss::Html::ArticleRules::Category do
  describe 'constants' do
    it 'keeps a single vocabulary home used by both adapters' do
      expect(Html2rss::Html::ArticleExtractor::CategoryExtractor::CATEGORY_TERMS)
        .to equal(described_class::CATEGORY_TERMS)
    end

    it 'does not treat layout label/section words as category terms' do
      expect(described_class::CATEGORY_TERMS).not_to include('label', 'labels', 'section', 'sections')
    end
  end

  describe '.class_match?' do
    it 'matches hyphenated class tokens, not layout substrings', :aggregate_failures do
      expect(described_class.class_match?('category-news post-tag')).to be(true)
      expect(described_class.class_match?('p-section__news__teaser')).to be(false)
      expect(described_class.class_match?('label-health')).to be(false)
    end
  end

  describe '.add_split_text!' do
    it 'splits newline-delimited labels and drops chrome values', :aggregate_failures do
      categories = Set.new
      described_class.add_split_text!(categories, "Politics\n\nRead more\nLaunch")
      expect(categories).to contain_exactly('Politics', 'Launch')
    end

    it 'keeps News taxonomy values while dropping CTA and date chrome', :aggregate_failures do
      categories = Set.new
      described_class.add_split_text!(categories, "News\nRead more\n12 March 2024\nInformatietype:")
      expect(categories).to contain_exactly('News')
    end
  end
end
