# frozen_string_literal: true

RSpec.describe Html2rss::Vocabulary do
  let(:languages) { described_class::ALL }
  let(:flags) { Regexp::IGNORECASE | Regexp::EXTENDED | Regexp::MULTILINE }
  let(:bare) { /(?<!\\)[[:space:]#]/ }

  describe '::ALL' do
    it 'lists the languages in a fixed order', :aggregate_failures do
      expect(languages.map(&:code)).to eq(%i[en de fr es it nl pl sv ja pt])
      expect(languages).to all(be_a(described_class::Language))
      expect(languages).to be_frozen
    end

    it 'has every language declare every concept, with NONE allowed', :aggregate_failures do
      languages.each do |language|
        expect(language.terms.keys).to match_array(described_class::CONCEPTS), "#{language.code} concepts"
        expect(language.terms).to be_frozen
      end
    end

    it 'holds only Portuguese pager nouns for pt' do
      pt = languages.last.terms.reject { |_concept, terms| terms.equal?(described_class::NONE) }

      expect(pt.keys).to eq([:pager_label])
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
      words = described_class.words(:path_vanity)

      expect(words).to be_a(Set).and be_frozen
      expect(words).to include('join', 'abonnieren', 'suscribirse', 's-abonner')
    end

    it 'keeps accented and unaccented forms as distinct words', :aggregate_failures do
      expect(described_class.words(:path_office)).to include('redacción', 'redaccion')
      expect(described_class.words(:type_marker)).to include('en directo', 'live blog', '速報')
    end

    it 'rejects a pattern concept and an unknown concept', :aggregate_failures do
      expect { described_class.words(:utility) }.to raise_error(KeyError)
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
      alternation = described_class.alternation(:recommended)

      expect(alternation).to be_frozen
      expect(alternation.split('|')).to include('recommended\s+for\s+you', 'recommandé\s+pour\s+vous')
    end

    it 'takes a fragment as written' do
      expect(described_class.alternation(:topic_lead).split('|')).to include('plus\s+d[\'’]infos?', 'altro')
    end

    it 'escapes a literal' do
      expect(described_class.alternation(:page_link)).to eq('prev|previous|next|older|newer|first|last')
    end

    it 'keeps a concept only some languages use to those languages', :aggregate_failures do
      expect(described_class.alternation(:clock_suffix)).to eq('Uhr')
      expect(described_class.alternation(:element_label)).to eq('PR')
      expect(described_class.alternation(:date_piece)).to eq('(?:\d{4}年)?\d{1,2}月\d{1,2}日')
    end

    it 'rejects a word concept and an unknown concept', :aggregate_failures do
      expect { described_class.alternation(:path_media) }.to raise_error(KeyError)
      expect { described_class.alternation(:nothing) }.to raise_error(KeyError)
    end
  end
end
