# frozen_string_literal: true

RSpec.describe Html2rss::Html::ArticleRules::Category do
  describe 'constants' do
    it 'keeps a single vocabulary home used by both adapters' do
      expect(Html2rss::Html::ArticleExtractor::CategoryExtractor::CATEGORY_TERMS)
        .to equal(described_class::CATEGORY_TERMS)
    end
  end

  describe '.add_split_text!' do
    it 'splits newline-delimited labels into the set' do
      categories = Set.new
      described_class.add_split_text!(categories, "News\n\nLaunch")
      expect(categories).to contain_exactly('News', 'Launch')
    end
  end
end
