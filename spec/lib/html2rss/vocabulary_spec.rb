# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers

RSpec.describe Html2rss::Vocabulary do
  let(:languages) { described_class::SHARED_LANGUAGES }
  let(:flags) { Regexp::IGNORECASE | Regexp::EXTENDED | Regexp::MULTILINE }
  let(:bare) { /(?<!\\)[[:space:]#]/ }

  describe '::SHARED_LANGUAGES' do
    # Every (concept, language) cell that holds no term, and nothing else: a human-language concept has terms in
    # all eleven shared languages. A suffix reading exists only in Japanese (the topic comes first there, so Japanese
    # has no lead-in either; Russian has none because its bare "more" and "about" are ordinary headline openers),
    # +page_link+ is the English-only pattern (the other languages are read through +page_link_label+), a date
    # piece and an element label exist in one language each, a clock suffix in German and Russian, the podcast
    # words are words of six languages and the unspaced (kana) ones exist in Japanese only. Russian lists a path
    # word only for the concepts whose Cyrillic segments occur in practice (+/видео/+, +/пресс-релизы/+,
    # +/помощь/+); the others are read through the Latin words every language shares. A page-only language (see
    # +PAGE_ONLY+, below) is no shared language and has its own rule.
    let(:none_cells) do
      all = %i[en de fr es it nl pl sv ja pt ru]
      cells = {
        path_section: %i[ru], path_article: %i[ru], path_profile: %i[ru], path_office: %i[ru],
        path_non_article: %i[ru], path_taxonomy: %i[ru], path_vanity: %i[ru], path_soft_utility: %i[ru],
        clock_suffix: all - %i[de ru],
        date_piece: all - %i[ja ru],
        element_label: all - %i[ja],
        list_more: all,
        read_more_suffix: all - %i[ja],
        topic_lead: %i[ja ru],
        topic_preposition: %i[ja],
        page_link: all - %i[en],
        page_link_label: %i[en],
        podcast_word: %i[de nl pl sv ja],
        podcast_unspaced: all - %i[ja]
      }
      cells
    end

    # A page-only language declares terms only for the concepts a page scope reads (path words, the scoped
    # patterns, the page patterns and the type markers), and no ambiguous term: it applies as a whole, on its own
    # pages.
    it 'has each page-only language declare only concepts that a page scope reads', :aggregate_failures do
      read_by_scope = described_class::SCOPED_WORDS + described_class::SCOPED_PATTERNS +
                      described_class::PAGE_PATTERNS + %i[type_marker]

      described_class::PAGE_ONLY.each do |language|
        declared = language.terms.select { |_concept, terms| terms.any? }.keys

        expect(declared - read_by_scope).to be_empty, "#{language.code} declares #{declared - read_by_scope}"
        expect(language.terms.keys).to match_array(described_class::CONCEPTS)
        expect(language.ambiguous).to be_empty
        expect(described_class::SHARED_LANGUAGES).not_to include(language)
      end
    end

    it 'reads exactly the listed page patterns and still rejects every other pattern concept', :aggregate_failures do
      expect(described_class::PAGE_PATTERNS).to eq(
        %i[utility_cta read_more list_more topic_lead topic_preposition read_more_suffix new_window_notice
           paid_label ad_word element_label field_label type_label clock_suffix date_piece
           pager_label page_link page_link_label]
      )
      unread = described_class::CONCEPTS - described_class::SCOPED_WORDS - described_class::SCOPED_PATTERNS -
               described_class::PAGE_PATTERNS - %i[type_marker]
      expect(unread).to eq(%i[podcast_word podcast_unspaced])
    end

    it 'lists the languages in a fixed order', :aggregate_failures do
      expect(languages.map(&:code)).to eq(%i[en de fr es it nl pl sv ja pt ru])
      expect(described_class::PAGE_ONLY).to eq([described_class::Zh, described_class::Ko, described_class::He,
                                                described_class::El, described_class::Uk, described_class::Ar,
                                                described_class::Fa, described_class::Hi, described_class::Th,
                                                described_class::Tr, described_class::Id, described_class::Vi,
                                                described_class::Cs, described_class::Hu,
                                                described_class::Ro, described_class::Da, described_class::No,
                                                described_class::Fi])
      expect(described_class::LANGUAGES).to eq(languages + described_class::PAGE_ONLY)
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

    it 'has terms in every language for each of the other concepts', :aggregate_failures do
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
      expect(described_class.alternation(:date_piece)).to start_with('(?:\d{4}年)?\d{1,2}月\d{1,2}日|')
      expect(described_class.alternation(:date_piece)).to include('ноябр', 'чера')
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
      expect(scopes.map(&:code)).to eq(
        %i[en de fr es it nl pl sv ja pt ru all zh ko he el uk ar fa hi th tr id vi cs hu ro da no fi]
      )
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

    it 'reads the Norwegian scope for no, nb and nn, with any region, in any case', :aggregate_failures do
      %w[no no-NO NO NO-no nb nb-NO NB NB-no nn nn-NO NN NN-no nb_NO nn-Latn-NO].each do |tag|
        expect(described_class[tag]).to be(described_class[:no]), tag
      end
      expect([described_class[:nb], described_class[:nn]]).to all(be(described_class[:no]))
      expect(described_class[:no].code).to eq(:no)
    end

    it 'maps no other language to a scope it does not own', :aggregate_failures do
      %w[da sv nl nds nbo no1].each do |tag|
        expect(described_class[tag]).not_to be(described_class[:no]), tag
      end
      expect(described_class['nbo']).to be(described_class[nil])
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

    it 'is the all scope plus its own terms, which no other scope has', :aggregate_failures do
      expect(chinese.ambiguous_words).to eq(everything.ambiguous_words)
      expect(chinese.alternations).to eq(everything.alternations)
      expect(chinese.own_alternation(:utility)).to include('关于我们').and include('關於我們')
      expect(chinese.own_alternation(:recommended)).to include('推荐阅读')
      expect(chinese.type_markers).to be_frozen
      own = [chinese, *%i[ko he el uk ar fa hi th tr id vi cs hu ro da no fi].map { described_class[_1] }]
      (described_class::SCOPES.values - own).each do |scope|
        expect(scope.own_alternations.values).to all(eq('')), scope.code.to_s
        expect(scope.own_words.values).to all(be_empty), scope.code.to_s
      end
    end

    it 'leaves out exactly the plain words of Chinese among the shared type markers', :aggregate_failures do
      plain = described_class::Zh.plain_words

      expect(plain).to eq(Set['独自', '写真'])
      expect(plain).to be_a(Set).and be_frozen
      expect(plain - described_class::Ja.terms.fetch(:type_marker)).to be_empty
      expect(described_class::Zh.terms.fetch(:type_marker)).to be_empty
      expect(chinese.type_markers).to eq(described_class.words(:type_marker) - plain)
      expect(chinese.type_markers).to include('速報', '詳報', '動画')
    end

    it 'defaults a language to no ambiguous term and no plain word, both frozen', :aggregate_failures do
      plain = described_class::Language.new(code: :xx, terms: {}.freeze)

      expect([plain.ambiguous, plain.plain_words]).to all(be_empty.and(be_frozen))
    end

    it 'takes the plain words from the page-only language, so another one keeps 独自 and 写真', :aggregate_failures do
      other = described_class::Language.new(code: :xx, plain_words: Set['速報'].freeze,
                                            terms: described_class::Zh.terms.merge(type_marker: %w[xx-tag]).freeze)
      scope = described_class.build_scope(:xx, described_class::SHARED_LANGUAGES, own: [other])

      expect(scope.type_markers).to include('独自', '写真', 'xx-tag')
      expect(scope.type_markers).to be_frozen
      expect(scope.type_markers).not_to include('速報')
      expect(described_class.build_scope(:yy, described_class::SHARED_LANGUAGES, own: []).type_markers)
        .to be(described_class.words(:type_marker))
    end

    it 'gives every other scope, all and ja included, the identical full marker set without Chinese terms',
       :aggregate_failures do
      own = [chinese, *%i[ko he el uk ar fa hi th tr id vi cs hu ro da no fi].map { described_class[_1] }]
      others = described_class::SCOPES.values - own

      expect(others.map(&:type_markers)).to all(equal(described_class.words(:type_marker)))
      expect(described_class.words(:type_marker)).to include('独自', '写真', '速報', '動画')
      expect(described_class.words(:type_marker)).not_to include('快讯', '獨家')
      expect(described_class[:ja].type_markers).to be(described_class[nil].type_markers)
    end

    # The tables of every language but Chinese are what the eleven shared language files compile to: a Chinese term
    # is in no shared table, so +all+, +ja+ and every other language read the same terms as before Chinese existed.
    it 'adds no Chinese term to a shared table, to the all scope or to any other language scope', :aggregate_failures do
      shared = described_class::SHARED_LANGUAGES
      terms = ->(concept) { shared.flat_map { _1.terms.fetch(concept) } }

      (described_class::PATTERN_CONCEPTS - described_class::SCOPED_PATTERNS).each do |concept|
        expect(described_class.alternation(concept)).to eq(described_class.compile(terms.call(concept))), concept.to_s
      end
      described_class::SCOPED_PATTERNS.each do |concept|
        flagged = described_class.ambiguous_terms(shared, concept)

        expect(described_class.unambiguous_alternation(concept))
          .to eq(described_class.compile(terms.call(concept) - flagged)), concept.to_s
        expect(everything.ambiguous_alternation(concept)).to eq(described_class.compile(flagged)), concept.to_s
      end
      (described_class::WORD_CONCEPTS - described_class::SCOPED_WORDS).each do |concept|
        expect(described_class.words(concept)).to eq(Set.new(terms.call(concept))), concept.to_s
      end
      described_class::SCOPED_WORDS.each do |concept|
        expect(everything.words(concept)).to eq(Set.new(terms.call(concept))), concept.to_s
      end
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

    it 'gives every page-only scope, Turkish and Indonesian included, every ambiguous term of every language',
       :aggregate_failures do
      everything = described_class[nil]

      described_class::PAGE_ONLY.each do |language|
        page = described_class[language.code]

        expect(page.ambiguous_words).to eq(everything.ambiguous_words), language.code.to_s
        expect(page.alternations).to eq(everything.alternations), language.code.to_s
      end
      expect(described_class[:sv].ambiguous_alternation(:utility)).to include('dela')
      expect(described_class[:de].ambiguous_alternation(:utility)).not_to include('dela')
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
                                               alternations: {}.freeze, own_words: { path_taxonomy: [] }.freeze,
                                               own_alternations: {}.freeze,
                                               type_markers: described_class.words(:type_marker))

      expect(overlapping.words(:path_taxonomy)).to eq(described_class.unambiguous_words(:path_taxonomy) | %w[tema])
    end

    it 'adds the own words of a page-only language to the shared Set', :aggregate_failures do
      own = described_class::Scope.new(code: :xx, ambiguous_words: { path_taxonomy: %w[tema] }.freeze,
                                       alternations: {}.freeze, own_words: { path_taxonomy: %w[ownword] }.freeze,
                                       own_alternations: {}.freeze, type_markers: described_class.words(:type_marker))

      expect(own.words(:path_taxonomy)).to eq(described_class.unambiguous_words(:path_taxonomy) | %w[tema ownword])
      expect(own.words(:path_taxonomy)).to be_frozen
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
      terms = described_class::SHARED_LANGUAGES.flat_map { _1.terms.fetch(:utility) }
      every = described_class.compile(terms).split('|')

      expect((shared + flagged).uniq).to match_array(every.uniq)
    end
  end

  describe '#own?' do
    it 'is true only for a scope with own terms', :aggregate_failures do
      expect(described_class[:zh].own?).to be(true)
      expect(%i[en ja de all].map { described_class[_1].own? }).to all(be(false))
    end
  end

  describe '.union' do
    it 'is the shared alternatives, widened by the own ones when there are any', :aggregate_failures do
      none = { read_more: '', utility_cta: '' }

      expect(described_class.union(:read_more, none)).to eq(described_class.alternation(:read_more))
      expect(described_class.union(:read_more, { read_more: 'lees-xx' }))
        .to eq("#{described_class.alternation(:read_more)}|lees-xx")
      expect(described_class.union(:utility_cta, none)).not_to include('|lees-xx')
    end
  end

  describe '.by_own_terms' do
    it 'builds one entry per distinct own-term set and key, shared by every scope without own terms',
       :aggregate_failures do
      calls = []
      table = described_class.by_own_terms(%i[read_more]) { |own, scope| (calls << [own, scope.code]).size }

      expect(table.keys).to eq(described_class::SCOPES.keys)
      expect(table.values.uniq.size).to eq(calls.size)
      expect(calls.size).to be < described_class::SCOPES.size
      expect(table).to be_frozen
      expect(table.fetch(:en)).to equal(table.fetch(:all))
    end

    it 'tells scopes apart by the key too', :aggregate_failures do
      by_code = described_class.by_own_terms(%i[read_more], key: :code.to_proc) { |_own, scope| scope.code }

      expect(by_code).to eq(described_class::SCOPES.keys.to_h { [_1, _1] })
    end

    it 'reads the own terms of a page-only scope', :aggregate_failures do
      own = nil
      described_class.by_own_terms(%i[read_more]) { |terms, scope| own = terms if scope.code == :zh }

      expect(own.fetch(:read_more)).to include('阅读全文')
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
