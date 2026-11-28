# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::ArticleRules::Category::Collector do
  let(:vocabulary) { Html2rss::Vocabulary[nil] }

  describe '#add_split' do
    it 'splits newline-delimited labels and drops chrome values', :aggregate_failures do
      collector = described_class.new(vocabulary:)
      collector.add_split("Politics\n\nRead more\nLaunch")
      expect(collector.to_a).to contain_exactly('Politics', 'Launch')
    end

    it 'keeps News taxonomy values while dropping CTA and date chrome', :aggregate_failures do
      collector = described_class.new(vocabulary:)
      collector.add_split("News\nRead more\n12 March 2024\nInformatietype:")
      expect(collector.to_a).to contain_exactly('News')
    end

    it 'strips each split line before storing' do
      collector = described_class.new(vocabulary:)
      collector.add_split(" Launch \n Politics ")
      expect(collector.to_a).to eq(%w[Launch Politics])
    end

    it 'ignores nil text' do
      collector = described_class.new(vocabulary:)
      collector.add_split(nil)
      expect(collector.to_a).to be_empty
    end
  end

  describe '#to_a properties' do
    it 'holds no duplicates and never raises', :aggregate_failures, :property do
      forall(PropCheck::Generators.array(TextGenerators.valid_text, max: 8)) do |texts|
        collector = described_class.new(vocabulary:)
        texts.each { |text| [collector.add(text), collector.add_split(text)] }
        expect(collector.to_a).to eq(collector.to_a.uniq)
      end
    end
  end

  describe '#add' do
    it 'keeps insertion order and drops duplicates', :aggregate_failures do
      collector = described_class.new(vocabulary:)
      collector.add('Politics')
      collector.add('Launch')
      collector.add('Politics')
      expect(collector.to_a).to eq(%w[Politics Launch])
    end

    it 'drops file-size labels, dated, cut-off and title-prefix values', :aggregate_failures do
      collector = described_class.new(vocabulary:, title: 'Topic: rest of the title')
      ['PDF 265 KB', 'Forschung // 26.11.2026', 'Forschung und Entwick...', 'Topic', 'Forschung'].each do |text|
        collector.add(text)
      end
      expect(collector.to_a).to eq(%w[Forschung])
    end

    it 'strips surrounding whitespace before storing' do
      collector = described_class.new(vocabulary:)
      collector.add("  Politics \n")
      expect(collector.to_a).to eq(%w[Politics])
    end

    it 'ignores blank text', :aggregate_failures do
      collector = described_class.new(vocabulary:)
      collector.add(nil)
      collector.add('   ')
      expect(collector.to_a).to be_empty
    end

    it 'rejects a value that echoes the article title' do
      collector = described_class.new(vocabulary:, title: 'Breaking Story')
      collector.add('breaking story')
      collector.add('Politics')
      expect(collector.to_a).to eq(%w[Politics])
    end

    it 'keeps a type chip because whole-line type chips are not rejected here' do
      collector = described_class.new(vocabulary:)
      collector.add('Video')
      expect(collector.to_a).to eq(%w[Video])
    end
  end
end
