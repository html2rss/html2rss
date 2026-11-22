# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/SpecFilePathFormat

# Pins which languages declare each ambiguous term, and what each page language then reads.
RSpec.describe Html2rss::Vocabulary do
  # concept => { term => the languages in which the term keeps its chrome meaning (and so applies) }
  let(:flagged) do
    {
      utility_prefix: { 'plus' => %i[en de es it nl pl sv pt] },
      utility: {
        'plus' => %i[en de es it nl pl sv pt], 'comment' => %i[en], 'ueber' => %i[de], 'über' => %i[de],
        'teilen' => %i[de], 'sobre' => %i[es pt], 'dela' => %i[sv], 'delen' => %i[nl],
        'comentário' => %i[pt], 'comentários' => %i[pt], '留言' => %i[zh]
      },
      path_vanity: { 'plus' => %i[en de es it nl pl sv pt] },
      path_soft_utility: { 'plus' => %i[en de es it nl pl sv pt] },
      path_chrome: { 'comment' => %i[en], 'ueber' => %i[de], 'sobre' => %i[es pt] },
      path_taxonomy: {
        'theme' => %i[en fr], 'themes' => %i[en fr], 'thema' => %i[de nl], 'themen' => %i[de],
        'tema' => %i[es it pt sv], 'temas' => %i[es pt], 'temat' => %i[pl], 'tematy' => %i[pl], 'テーマ' => %i[ja]
      },
      path_section: { 'entradas' => %i[es pt] },
      path_article: { 'entrada' => %i[es pt] }
    }
  end
  let(:text) { ->(lang) { Html2rss::LinkDestination::TextClassifier.new(vocabulary: described_class[lang]) } }
  let(:path) do
    lambda do |lang, term|
      Html2rss::LinkDestination::PathClassifier.new([term, 'harbor-ferry-schedule'],
                                                    vocabulary: described_class[lang])
    end
  end
  # Each way of reading a concept: a classifier call on the term alone.
  let(:readers) do
    {
      utility_prefix: ->(lang, term) { text.call(lang).utility_prefix?(term) },
      utility: ->(lang, term) { text.call(lang).utility?(term) },
      path_vanity: ->(lang, term) { path.call(lang, term).vanity_path? },
      path_soft_utility: ->(lang, term) { path.call(lang, term).utility_path? },
      path_chrome: ->(lang, term) { path.call(lang, term).utility_path? },
      path_taxonomy: ->(lang, term) { path.call(lang, term).taxonomy_path? },
      path_section: ->(lang, term) { path.call(lang, term).content_path? },
      path_article: ->(lang, term) { path.call(lang, term).content_path? }
    }
  end
  let(:scopes) { described_class::ALL.map(&:code) + [nil] }

  describe 'declared terms' do
    it 'are exactly the pinned ambiguous terms per concept, by language' do
      declared = described_class::ALL.each_with_object({}) do |lang, all|
        lang.ambiguous.each do |concept, terms|
          terms.each { |term| ((all[concept] ||= {})[term] ||= []) << lang.code }
        end
      end

      sorted = ->(table) { table.transform_values { |terms| terms.transform_values(&:sort) } }

      expect(sorted.call(declared)).to eq(sorted.call(flagged))
    end
  end

  %i[utility_prefix utility path_vanity path_soft_utility path_chrome path_taxonomy path_section
     path_article].each do |concept|
    describe concept.to_s do
      it 'applies each ambiguous term in its languages and the all scope, and ignores it elsewhere',
         :aggregate_failures do
        flagged.fetch(concept).each do |term, languages|
          scopes.each do |lang|
            applies = lang.nil? || languages.include?(lang)

            expect(readers.fetch(concept).call(lang, term)).to be(applies), "#{term.inspect} for #{lang.inspect}"
          end
          expect(readers.fetch(concept).call(:all, term)).to be(true), "#{term.inspect} for :all"
        end
      end
    end
  end

  describe 'a Chinese page' do
    %i[utility_prefix utility path_vanity path_soft_utility path_chrome path_taxonomy path_section path_article]
      .each do |concept|
      it "applies every ambiguous #{concept} term of Chinese, and no ambiguous term of another language",
         :aggregate_failures do
        flagged.fetch(concept).to_a.product(%i[zh zh-Hant zh-Hans-CN]).each do |(term, languages), lang|
          expect(readers.fetch(concept).call(lang, term)).to be(languages.include?(:zh)), "#{term.inspect} #{lang}"
        end
      end
    end

    it 'does not read an ambiguous Latin term, as a page in no listed language does not', :aggregate_failures do
      expect(text.call(:zh).utility?('Dela Cruz wins election')).to be(false)
      expect(text.call('zh-Hant').utility?('Dela Cruz wins election')).to be(false)
      expect(text.call(nil).utility?('Dela Cruz wins election')).to be(true)
    end

    it 'keeps the Japanese words 独自 and 写真 as title markers in every scope but its own', :aggregate_failures do
      noise = ->(marker, lang) { Html2rss::Article::Title.noise_piece?(marker, vocabulary: described_class[lang]) }

      [nil, :all, :ja, :en, :de, :sv, 'ja-JP', 'en-US'].product(%w[独自 写真]).each do |lang, marker|
        expect(noise.call(marker, lang)).to be(true), "#{marker} #{lang.inspect}"
      end
      %w[独自 写真].product(%i[zh zh-Hant zh-Hans-CN]).each { |marker, lang| expect(noise.call(marker, lang)).to be(false) }
      %w[快讯 獨家].each { expect(noise.call(_1, :zh)).to be(true) }
    end
  end

  describe 'premium' do
    it 'is an international subscription word: unflagged, and read in every language', :aggregate_failures do
      expect(described_class::ALL.flat_map { _1.ambiguous.values.flatten }).not_to include('premium')
      scopes.each do |lang|
        expect(text.call(lang).utility?('Premium')).to be(true), lang.inspect
        expect(text.call(lang).utility_prefix?('Premium members')).to be(true), lang.inspect
        expect(path.call(lang, 'premium').vanity_path?).to be(true), lang.inspect
      end
    end
  end

  describe 'headlines' do
    it 'keeps "Dela Cruz wins election" and "Plus de 100 morts" out of utility where the word is not chrome',
       :aggregate_failures do
      expect(text.call(:en).utility?('Dela Cruz wins election')).to be(false)
      expect(text.call(:sv).utility?('Dela Cruz wins election')).to be(true)
      expect(text.call(:fr).utility?('Plus de 100 morts')).to be(false)
      expect(text.call(:fr).utility_prefix?('Plus de 100 morts')).to be(false)
      expect(text.call(:de).utility_prefix?('Plus Abo')).to be(true)
    end

    it 'keeps /tema/ out of the taxonomy on a page in English' do
      expect(path.call(:en, 'tema').taxonomy_path?).to be(false)
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/SpecFilePathFormat
