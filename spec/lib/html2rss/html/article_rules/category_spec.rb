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
      expect(described_class.class_match?(%w[category-news post-tag])).to be(true)
      expect(described_class.class_match?(%w[p-section__news__teaser])).to be(false)
      expect(described_class.class_match?(%w[label-health])).to be(false)
    end

    it 'is case-insensitive and false for no classes', :aggregate_failures do
      expect(described_class.class_match?(%w[Post-TAGS])).to be(true)
      expect(described_class.class_match?([])).to be(false)
    end
  end
end
