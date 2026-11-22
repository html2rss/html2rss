# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers

RSpec.describe Html2rss::Vocabulary do
  let(:languages) { described_class::ALL }
  let(:flags) { Regexp::IGNORECASE | Regexp::EXTENDED | Regexp::MULTILINE }
  let(:bare) { /(?<!\\)[[:space:]#]/ }

  describe '::ALL' do
    # Every (concept, language) cell that holds no term, and nothing else: a human-language concept has terms in
    # all twelve languages. A suffix reading exists only in Japanese (the topic comes first there, so Japanese has
    # no lead-in either; Russian has none because its bare "more" and "about" are ordinary headline openers, and
    # Chinese has neither),
    # +page_link+ is the English-only pattern (the other languages are read through +page_link_label+), a date
    # piece and an element label exist in one language each, a clock suffix in German and Russian, the podcast
    # words are words of six languages and the unspaced (kana, Han) ones exist in Japanese and Chinese only.
    # Russian lists a path
    # word only for the concepts whose Cyrillic segments occur in practice (+/видео/+, +/пресс-релизы/+,
    # +/помощь/+); the others are read through the Latin words every language shares.
    let(:none_cells) do
      all = %i[en de fr es it nl pl sv ja pt ru zh]
      {
        path_section: %i[ru zh], path_article: %i[ru zh], path_profile: %i[ru zh], path_office: %i[ru zh],
        path_non_article: %i[ru zh], path_taxonomy: %i[ru zh], path_vanity: %i[ru zh], path_soft_utility: %i[ru zh],
        path_chrome: %i[zh], path_media: %i[zh], path_deep_post_context: %i[zh],
        clock_suffix: all - %i[de ru],
        date_piece: all - %i[ja],
        element_label: all - %i[ja],
        read_more_suffix: all - %i[ja],
        topic_lead: %i[ja ru zh],
        topic_preposition: %i[ja zh],
        page_link: all - %i[en],
        page_link_label: %i[en],
        podcast_word: %i[de nl pl sv ja zh],
        podcast_unspaced: all - %i[ja zh]
      }
    end

    it 'lists the languages in a fixed order', :aggregate_failures do
      expect(languages.map(&:code)).to eq(%i[en de fr es it nl pl sv ja pt ru zh])
      expect(languages).to all(be_a(described_class::Language))
      expect(languages).to be_frozen
    end

    it 'has every language declare every concept', :aggregate_failures do
      languages.each do |language|
        expect(language.terms.keys).to match_array(described_class::CONCEPTS), "#{language.code} concepts"
        expect(language.terms).to be_frozen
      end
    end

    it 'leaves a concept without terms only in the listed cells, and lists no cell that has terms',
       :aggregate_failures do
      cells = languages.flat_map do |language|
        language.terms.select { |_concept, terms| terms.empty? }.keys.map { [_1, language.code] }
      end

      expect(cells.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }).to eq(none_cells)
      expect(languages.flat_map { _1.terms.values }.select(&:empty?)).to all(be(described_class::NONE))
    end

    it 'has terms in all twelve languages for each of the other concepts', :aggregate_failures do
      (described_class::CONCEPTS - none_cells.keys).each do |concept|
        expect(languages.reject { _1.terms.fetch(concept).any? }).to be_empty, concept.to_s
      end
    end
  end

  describe '::CONCEPTS' do
    it 'is the word concepts then the pattern concepts, without overlap', :aggregate_failures do
      expect(described_class::CONCEPTS).to eq(described_class::WORD_CONCEPTS + described_class::PATTERN_CONCEPTS)
      expect(described_class::CONCEPTS.uniq).to eq(described_class::CONCEPTS)
      expect(described_class::CONCEPTS).to be_frozen
    end
  end

  describe 'terms' do
    it 'are exact strings for a word concept' do
      terms = languages.flat_map { |language| described_class::WORD_CONCEPTS.flat_map { language.terms.fetch(_1) } }

      expect(terms).to all(be_a(String).and(satisfy { !_1.empty? && _1 == _1.strip && !_1.include?('  ') }))
    end

    it 'are literal strings or flagless fragments for a pattern concept', :aggregate_failures do
      terms = languages.flat_map { |language| described_class::PATTERN_CONCEPTS.flat_map { language.terms.fetch(_1) } }

      expect(terms.grep(String)).to all(satisfy { !_1.empty? && _1 == _1.strip && !_1.include?('  ') })
      expect(terms.grep(Regexp)).to all(satisfy { _1.options.nobits?(flags) && !_1.source.match?(bare) })
      expect(terms.size).to eq(terms.grep(String).size + terms.grep(Regexp).size)
    end
  end

  describe '.words' do
    it 'unions the exact terms of all languages into a frozen set', :aggregate_failures do
      words = described_class.words(:type_marker)

      expect(words).to be_a(Set).and be_frozen
      expect(words).to include('live blog', 'liveticker', 'en directo', '速報')
    end

    it 'keeps accented and unaccented forms as distinct words', :aggregate_failures do
      expect(described_class[nil].words(:path_office)).to include('redacción', 'redaccion')
      expect(described_class.words(:type_marker)).to include('vídeo', 'video')
    end

    it 'rejects a pattern concept, a scoped concept and an unknown concept', :aggregate_failures do
      expect { described_class.words(:utility) }.to raise_error(KeyError)
      expect { described_class.words(:path_office) }.to raise_error(KeyError)
      expect { described_class.words(:nothing) }.to raise_error(KeyError)
    end
  end

  describe '.compile' do
    it 'turns each space of a literal into a whitespace run', :aggregate_failures do
      expect(described_class.compile(['view all', 'login'])).to eq('view\s+all|login')
      expect(described_class.compile(['a b c'])).to eq('a\s+b\s+c')
    end

    it 'escapes a literal for use under the x and i flags', :aggregate_failures do
      expect(described_class.compile(['a.b', 'c#d', 'e-f'])).to eq('a\.b|c\#d|e\-f')
      expect(described_class.compile(['x|y']).then { Regexp.new("\\A(?:#{_1})\\z", Regexp::EXTENDED) }).to match('x|y')
    end

    it 'takes a fragment as written, flags dropped' do
      expect(described_class.compile([/s['’]abonner/i, /a\s+b/, 'c'])).to eq('s[\'’]abonner|a\s+b|c')
    end

    it 'returns a frozen string, empty without terms', :aggregate_failures do
      expect(described_class.compile([])).to eq('')
      expect(described_class.compile(%w[a b])).to be_frozen
    end

    it 'rejects any other term' do
      expect { described_class.compile([:sym]) }.to raise_error(NoMatchingPatternError)
    end
  end

  describe '.alternation' do
    it 'compiles a literal with each space matching any whitespace run', :aggregate_failures do
      alternation = described_class.alternation(:type_label)

      expect(alternation).to be_frozen
      expect(alternation.split('|')).to include('article\s+type', 'content\s+type')
    end

    it 'takes a fragment as written' do
      expect(described_class.alternation(:topic_lead).split('|')).to include('plus\s+d[\'’]infos?', 'altro')
    end

    it 'escapes a literal' do
      expect(described_class.alternation(:page_link)).to eq('prev|previous|next|older|newer|first|last')
    end

    it 'keeps first and last words out of the page link labels, whatever the language', :aggregate_failures do
      labels = described_class.alternation(:page_link_label)

      expect(described_class.alternation(:page_link)).to eq(described_class::En.terms.fetch(:page_link).join('|'))
      expect(labels).to include('suivante?', '次へ')
      expect(labels).not_to match(/premi|primer|primo|erste|eerste|pierwsz|f(?:ö|o)rsta|最初|primeir|dernier|last/i)
    end

    it 'keeps a concept only some languages use to those languages', :aggregate_failures do
      expect(described_class.alternation(:clock_suffix)).to eq('Uhr|мск')
      expect(described_class.alternation(:element_label)).to eq('PR')
      expect(described_class.alternation(:date_piece)).to eq('(?:\d{4}年)?\d{1,2}月\d{1,2}日')
    end

    it 'rejects a word concept, a scoped concept and an unknown concept', :aggregate_failures do
      expect { described_class.alternation(:path_media) }.to raise_error(KeyError)
      expect { described_class.alternation(:utility) }.to raise_error(KeyError)
      expect { described_class.alternation(:nothing) }.to raise_error(KeyError)
    end
  end

  describe '.[]' do
    let(:scopes) { described_class::SCOPES.values }

    it 'returns one frozen scope per language, plus all, each the identical object on every lookup',
       :aggregate_failures do
      expect(scopes.map(&:code)).to eq(%i[en de fr es it nl pl sv ja pt ru zh all])
      expect(scopes).to all(be_frozen)
      expect(scopes.map { described_class[_1.code] }).to eq(scopes)
      expect(scopes.zip(scopes.map { described_class[_1.code] })).to all(satisfy { |a, b| a.equal?(b) })
      expect(described_class['de']).to be(described_class[:de])
    end

    it 'reduces a regional tag to its primary tag, case-insensitively', :aggregate_failures do
      expect(described_class['de-AT']).to be(described_class[:de])
      expect(described_class['DE_at']).to be(described_class[:de])
      expect(described_class[' Sv-FI ']).to be(described_class[:sv])
      expect(described_class['ja-JP-u-ca-japanese']).to be(described_class[:ja])
    end

    it 'reduces a script-tagged language to its primary tag', :aggregate_failures do
      expect(described_class['de-Latn']).to be(described_class[:de])
      expect(described_class['ja-Jpan-JP']).to be(described_class[:ja])
      expect(described_class['sv_Latn_SE']).to be(described_class[:sv])
    end

    it 'maps nil, blank, malformed, unsupported and hostile values to the one all scope', :aggregate_failures do
      all = described_class[nil]

      expect(all.code).to eq(:all)
      [:all, '', '   ', 'x', 'deutsch', 'de@evil', 'xx', 'tlh', "de\nfr", '../de', 'de-' * 40, 12, [], {}, Object.new,
       :'', :xx].each do |value|
        expect(described_class[value]).to be(all), value.inspect
      end
    end

    it 'keeps the table closed: a lookup never adds an entry', :aggregate_failures do
      expect { %w[zz qq-QQ nonsense].each { described_class[_1] } }
        .not_to(change { [described_class::SCOPES.size, described_class::SCOPES.keys] })
      expect(described_class::SCOPES).to be_frozen
    end
  end

  describe 'the Chinese scope' do
    let(:chinese) { described_class[:zh] }
    let(:everything) { described_class[nil] }

    it 'resolves every Chinese tag, script and region included, to the one shared scope', :aggregate_failures do
      %w[zh ZH zh-Hant zh-Hans zh-Hans-CN zh_TW zh-Hant-HK].each { expect(described_class[_1]).to be(chinese), _1 }
      expect(chinese.code).to eq(:zh)
      expect(chinese).to be_frozen
    end

    it 'applies only its own ambiguous terms, like every other language scope', :aggregate_failures do
      expect(chinese.ambiguous_words).not_to be(everything.ambiguous_words)
      expect(chinese.words(:path_taxonomy)).not_to include('thema')
      expect(chinese.type_markers).to be_frozen
    end

    it 'leaves out exactly the Chinese words among the type markers', :aggregate_failures do
      expect(described_class::CHINESE_WORDS).to eq(Set['独自', '写真'])
      expect(described_class::CHINESE_WORDS).to be_a(Set).and be_frozen
      expect(described_class::CHINESE_WORDS - described_class::Ja.terms.fetch(:type_marker)).to be_empty
      expect(chinese.type_markers).to eq(described_class.words(:type_marker) - described_class::CHINESE_WORDS)
    end

    it 'gives every other scope, all and ja included, the identical full marker set', :aggregate_failures do
      others = described_class::SCOPES.values - [chinese]

      expect(others.map(&:type_markers)).to all(equal(described_class.words(:type_marker)))
      expect(described_class.words(:type_marker)).to include('独自', '写真', '速報', '動画', '快讯', '獨家')
      expect(described_class[:ja].type_markers).to include('独自', '写真')
      expect(described_class[nil].type_markers).to include('独自', '写真')
      expect(described_class[:ja].type_markers).to be(described_class[nil].type_markers)
    end
  end

  describe 'ambiguous terms' do
    let(:scoped) { described_class::SCOPED_WORDS + described_class::SCOPED_PATTERNS }

    it 'are listed only for a scoped concept, and are terms of that concept', :aggregate_failures do
      languages.each do |language|
        expect(language.ambiguous.keys - scoped).to be_empty, "#{language.code} flags an unscoped concept"
        language.ambiguous.each do |concept, terms|
          expect(language.terms.fetch(concept)).to include(*terms), "#{language.code} #{concept}"
          expect(terms).to eq(terms.uniq)
        end
      end
    end

    it 'carry one consistent flag for a term every language that lists it', :aggregate_failures do
      scoped.each do |concept|
        listed = languages.flat_map { |language| language.terms.fetch(concept).map { [_1, language] } }
        listed.group_by(&:first).each do |term, pairs|
          flags = pairs.map { |_, language| language.ambiguous.fetch(concept, described_class::NONE).include?(term) }
          expect(flags.uniq.size).to eq(1), "#{concept} #{term.inspect} is flagged in only some languages"
        end
      end
    end

    it 'default to none for a language that declares none' do
      expect(described_class::Language.new(code: :xx, terms: {}).ambiguous).to eq({}).and be_frozen
    end
  end

  describe '.ambiguous_terms' do
    let(:one) { described_class::Language.new(code: :xx, terms: {}, ambiguous: { utility: ['dela', /s['’]x/] }.freeze) }
    let(:two) { described_class::Language.new(code: :yy, terms: {}, ambiguous: { utility: %w[dela zed] }.freeze) }

    it 'joins the flagged terms of the languages in order, without repeats', :aggregate_failures do
      terms = described_class.ambiguous_terms([one, two], :utility)

      expect(terms).to eq(['dela', /s['’]x/, 'zed'])
      expect(terms).to be_frozen
    end

    it 'is empty for a concept no language flags', :aggregate_failures do
      expect(described_class.ambiguous_terms([one, two], :path_media)).to eq([])
      expect(described_class.ambiguous_terms([], :utility)).to eq([])
    end
  end

  describe '.build_scope' do
    let(:one) do
      described_class::Language.new(code: :xx, terms: {},
                                    ambiguous: { utility: ['dela', /s['’]x/], path_vanity: %w[plus] }.freeze)
    end
    let(:two) { described_class::Language.new(code: :yy, terms: {}, ambiguous: { utility: %w[dela zed] }.freeze) }
    let(:scope) { described_class.build_scope(:both, [one, two]) }

    it 'keeps its code and every scoped concept, frozen', :aggregate_failures do
      expect(scope).to be_frozen.and have_attributes(code: :both)
      expect(scope.ambiguous_words.keys).to eq(described_class::SCOPED_WORDS)
      expect(scope.alternations.keys).to eq(described_class::SCOPED_PATTERNS)
      expect([scope.ambiguous_words, scope.alternations]).to all(be_frozen)
    end

    it 'reads every language\'s type markers, as the one shared set', :aggregate_failures do
      expect(scope.type_markers).to be(described_class.words(:type_marker))
      expect(scope.type_markers).to include('速報', 'video')
    end

    it 'holds the ambiguous words and alternatives of its languages only', :aggregate_failures do
      expect(scope.ambiguous_words.fetch(:path_vanity)).to eq(%w[plus])
      expect(scope.ambiguous_words.fetch(:path_media)).to eq([])
      expect(scope.ambiguous_alternation(:utility)).to eq('dela|s[\'’]x|zed')
      expect(scope.ambiguous_alternation(:recommended)).to eq('')
    end
  end

  describe '.[] allocation' do
    it 'allocates nothing for nil, an exact tag or a symbol (the least of several runs, to shed GC.stat noise)',
       :aggregate_failures do
      [nil, 'de', :de].each do |lang|
        deltas = Array.new(5) do
          before = GC.stat(:total_allocated_objects)
          described_class[lang]
          GC.stat(:total_allocated_objects) - before
        end

        expect(deltas.min).to eq(0), lang.inspect
      end
    end
  end

  describe 'scope' do
    it 'applies an unambiguous term in every scope and an ambiguous one in its own language and all',
       :aggregate_failures do
      en = described_class[:en]

      expect(described_class[nil].words(:path_vanity)).to include('plus', 'subscribe')
      expect(en.words(:path_vanity)).to include('plus', 'subscribe')
      expect(described_class[:fr].words(:path_vanity)).to include('subscribe')
      expect(described_class[:fr].words(:path_vanity)).not_to include('plus')
      expect(described_class[nil].words(:path_vanity)).to include('plus', 'subscribe')
    end

    it 'builds a frozen Set where a scope adds an ambiguous word', :aggregate_failures do
      words = described_class[:es].words(:path_taxonomy)

      expect(words).to be_frozen.and include('tema', 'category')
      expect(described_class[:es].words(:path_taxonomy)).not_to be(words)
    end

    it 'unions the shared Set with the ambiguous words, whatever they overlap', :aggregate_failures do
      overlapping = described_class::Scope.new(code: :xx, ambiguous_words: { path_taxonomy: %w[category tema] }.freeze,
                                               alternations: {}.freeze,
                                               type_markers: described_class.words(:type_marker))

      expect(overlapping.words(:path_taxonomy)).to eq(described_class.unambiguous_words(:path_taxonomy) | %w[tema])
    end

    it 'reuses the identical shared Set where a scope adds no ambiguous word', :aggregate_failures do
      shared = described_class.unambiguous_words(:path_vanity)

      expect(described_class[:ja].words(:path_vanity)).to be(shared)
      expect(described_class[:fr].words(:path_vanity)).to be(shared)
      expect(described_class[:de].words(:path_vanity)).not_to be(shared)
      expect(described_class::SCOPES.values.map { _1.words(:path_office) }.uniq(&:object_id).size).to eq(1)
    end

    it 'holds the ambiguous alternatives of its own language only', :aggregate_failures do
      expect(described_class[:sv].ambiguous_alternation(:utility)).to eq('dela|plus')
      expect(described_class[:en].ambiguous_alternation(:utility)).not_to include('dela')
      expect(described_class[:all].ambiguous_alternation(:utility).split('|')).to include('dela', 'sobre', 'plus')
      expect(described_class[:ja].ambiguous_alternation(:utility)).to eq('')
    end

    it 'splits the all-language terms into the shared and the ambiguous parts', :aggregate_failures do
      shared = described_class.unambiguous_alternation(:utility).split('|')
      flagged = described_class[:all].ambiguous_alternation(:utility).split('|')

      expect(shared).to include('contact', 'subscribe')
      expect(shared).not_to include('dela', 'plus')
      every = described_class.compile(languages.flat_map { _1.terms.fetch(:utility) }).split('|')

      expect((shared + flagged).uniq).to match_array(every.uniq)
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
