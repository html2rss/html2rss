# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::ArticleRules::Category do
  describe 'constants' do
    it 'does not treat layout label/section words as category terms' do
      expect(described_class::CATEGORY_TERMS).not_to include('label', 'labels', 'section', 'sections')
    end
  end

  describe '.junk?' do
    it 'flags file-size labels, dates, cut-off text and the title prefix', :aggregate_failures do
      expect(described_class.junk?('PDF 265 KB')).to be(true)
      expect(described_class.junk?('Forschung // 26.11.2026')).to be(true)
      expect(described_class.junk?('Forschung und Entwick...')).to be(true)
      expect(described_class.junk?('Topic', title: 'Topic: rest of title')).to be(true)
    end

    it 'flags a whole or piece-wise date', :aggregate_failures do
      expect(described_class.junk?('12 March 2024')).to be(true)
      expect(described_class.junk?('Ausgabe | 2026-11-26')).to be(true)
    end

    it 'keeps version strings', :aggregate_failures do
      expect(described_class.junk?('Python 3.12')).to be(false)
      expect(described_class.junk?('v2.10')).to be(false)
      expect(described_class.junk?('Python 3.12.10')).to be(false)
      expect(described_class.junk?('Release v2.10.15')).to be(false)
    end

    it 'keeps ordinary labels', :aggregate_failures do
      expect(described_class.junk?('Forschung')).to be(false)
      expect(described_class.junk?('Topic', title: 'Another title: Topic')).to be(false)
      expect(described_class.junk?('Topic', title: 'No colon')).to be(false)
      expect(described_class.junk?('Topic', title: nil)).to be(false)
    end

    it 'handles a very long run of spaces', :aggregate_failures do
      expect(described_class.junk?("#{' ' * 50_000}x")).to be(false)
      expect(described_class.junk?("x#{' ' * 50_000}-")).to be(false)
    end

    it 'matches the title prefix only before a colon, ignoring case and spacing', :aggregate_failures do
      expect(described_class.junk?('Topic', title: 'Topic')).to be(false)
      expect(described_class.junk?('topic', title: ' Topic : rest')).to be(true)
    end
  end

  describe '.drop_shared' do
    it 'drops values every item carries, ignoring case', :aggregate_failures do
      lists = [%w[News Sport], ['news'], %w[NEWS Art]]

      expect(described_class.drop_shared(lists)).to eq([['Sport'], [], ['Art']])
    end

    it 'keeps a value missing from one item and a single item as is', :aggregate_failures do
      expect(described_class.drop_shared([%w[News], []])).to eq([%w[News], []])
      expect(described_class.drop_shared([%w[News]])).to eq([%w[News]])
    end

    it 'keeps a value shared by only two items' do
      expect(described_class.drop_shared([%w[News A], %w[News B]])).to eq([%w[News A], %w[News B]])
    end

    it 'drops a value shared by exactly three items' do
      expect(described_class.drop_shared([%w[News A], %w[News B], %w[News]])).to eq([%w[A], %w[B], []])
    end
  end

  describe 'properties' do
    it 'reads junk? as total over any text', :property do
      forall(TextGenerators.valid_text, TextGenerators.valid_text) do |value, title|
        expect { described_class.junk?(value, title:) }.not_to raise_error
      end
    end

    it 'keeps each output list an ordered subset of its input list', :property do
      forall(TextGenerators.category_lists) do |lists|
        pairs = described_class.drop_shared(lists).zip(lists)
        expect(pairs.map { |out, list| out == list.select { |value| out.include?(value) } }).to all(be(true))
      end
    end

    it 'leaves no value common to every output list when there are three or more', :property do
      forall(TextGenerators.category_lists.where { _1.size >= 3 }) do |lists|
        folded = described_class.drop_shared(lists).map { |out| out.map(&:downcase) }
        expect(folded.reduce(:&)).to be_empty
      end
    end

    it 'never drops a value missing from at least one input list', :property do
      forall(TextGenerators.category_lists) do |lists|
        folded = lists.map { |list| list.map(&:downcase) }
        dropped = lists.zip(described_class.drop_shared(lists)).flat_map { |list, out| list - out }
        expect(dropped.reject { |value| folded.all? { _1.include?(value.downcase) } }).to be_empty
      end
    end

    it 'reads 50_000 character adversarial values in bounded time' do
      seconds = TextGenerators.slowest_seconds(TextGenerators.adversarial_texts(prefix: 'x', suffix: '1')) do |text|
        described_class.junk?(text, title: text)
      end
      expect(seconds).to be < TextGenerators::TIME_BUDGET
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
