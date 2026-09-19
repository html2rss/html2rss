# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::PostProcessors::Gsub do
  subject { described_class.new(value, context).call }

  let(:context) { Html2rss::Selectors::StepEnv.new(step_config:) }
  let(:value) { 'hello' }

  it { expect(described_class).to be < Html2rss::Selectors::PostProcessors::Base }

  context 'with args validation' do
    context 'without pattern option' do
      let(:step_config) { { replacement: 'world' } }

      it do
        expect { subject }.to raise_error(Html2rss::Selectors::PostProcessors::MissingOption,
                                          /The `pattern` option is missing in: {/)
      end
    end

    context 'without replacement option' do
      let(:step_config) { { pattern: 'world' } }

      it do
        expect { subject }.to raise_error(Html2rss::Selectors::PostProcessors::MissingOption,
                                          /The `replacement` option is missing in: {/)
      end
    end

    context 'without replacement option not being a String or Hash' do
      let(:step_config) { { pattern: 'world', replacement: [] } }

      it do
        expect { subject }.to raise_error(Html2rss::Selectors::PostProcessors::InvalidType,
                                          /The type of `replacement` must be String or Hash, but is: Array in: {/)
      end
    end
  end

  context 'with string pattern' do
    context 'with string replacement' do
      let(:value) { 'Foo bar and boo' }
      let(:step_config) { { pattern: 'boo', replacement: 'baz' } }

      it { is_expected.to eq 'Foo bar and baz' }
    end
  end

  context 'with pattern being a Regexp as String' do
    context 'with hash replacement' do
      let(:step_config) { { pattern: '/[eo]/', replacement: { 'e' => 3, 'o' => '*' } } }

      it { is_expected.to eq 'h3ll*' }
    end

    context 'with single character string' do
      let(:step_config) { { pattern: '/', replacement: 'X' } }

      it { is_expected.to eq 'hello' }
    end

    context 'with three character string with slashes' do
      let(:step_config) { { pattern: '/e/', replacement: 'X' } }

      it { is_expected.to eq 'hXllo' }
    end
  end

  context 'with whitespace and empty string patterns' do
    let(:step_config) { { pattern: '^\\s*$', replacement: 'Untitled' } }

    context 'with empty string' do
      let(:value) { '' }

      it { is_expected.to eq 'Untitled' }
    end

    context 'with whitespace only string' do
      let(:value) { '   ' }

      it { is_expected.to eq 'Untitled' }
    end

    context 'with mixed whitespace string' do
      let(:value) { " \t\n " }

      it { is_expected.to eq 'Untitled' }
    end

    context 'with non-empty string containing whitespace' do
      let(:value) { '  hello  ' }

      it { is_expected.to eq '  hello  ' }
    end

    context 'with newlines and tabs only' do
      let(:value) { "\n\t\n" }

      it { is_expected.to eq 'Untitled' }
    end
  end

  # Ordinary YAML must stay valid. Nested quantifiers and the byte cap are the only rejects.
  # Overlapping alternation stays accepted (star-height residual, not this bound).
  describe '.compiled_pattern' do
    ordinary_patterns = [
      { label: 'literal replacement', pattern: 'boo', value: 'Foo bar and boo', replacement: 'baz',
        expected: 'Foo bar and baz' },
      { label: 'slash-wrapped character class', pattern: '/[eo]/', value: 'hello',
        replacement: { 'e' => 3, 'o' => '*' }, expected: 'h3ll*' },
      { label: 'whitespace-only anchor', pattern: '^\\s*$', value: '   ', replacement: 'Untitled',
        expected: 'Untitled' },
      { label: 'single quantifier', pattern: 'a+', value: 'aaa', replacement: 'b', expected: 'b' },
      { label: 'sibling quantifiers', pattern: 'a+b*', value: 'aaabbb', replacement: 'x', expected: 'x' },
      { label: 'possessive quantifier', pattern: 'a++', value: 'aaa', replacement: 'b', expected: 'b' },
      { label: 'plus inside a character class', pattern: '[a+]+', value: 'a+', replacement: 'x',
        expected: 'x' },
      { label: 'overlapping alternation', pattern: '(a|aa)+', value: 'aaa', replacement: 'x', expected: 'x' }
    ].freeze

    it 'publishes a 256-byte pattern cap' do
      expect(described_class::MAX_PATTERN_BYTES).to eq(256)
    end

    ordinary_patterns.each do |row|
      it "keeps #{row[:label]} valid" do
        step_config = { pattern: row[:pattern], replacement: row[:replacement] }
        env = Html2rss::Selectors::StepEnv.new(step_config:)
        expect(described_class.new(row[:value], env).call).to eq(row[:expected])
      end
    end

    %w[(a+)+ (a*)* (?:a+)+].each do |pattern|
      it "rejects nested quantifiers in #{pattern}" do
        expect { described_class.compiled_pattern(pattern) }
          .to raise_error(ArgumentError, 'pattern contains nested quantifiers')
      end
    end

    it 'rejects nested quantifiers before substitution' do
      processor = described_class.new(
        'aaa',
        Html2rss::Selectors::StepEnv.new(step_config: { pattern: '(a+)+', replacement: 'x' })
      )

      expect { processor.call }.to raise_error(ArgumentError, 'pattern contains nested quantifiers')
    end

    it 'rejects a source longer than the byte cap' do
      over = 'a' * (described_class::MAX_PATTERN_BYTES + 1)

      expect { described_class.compiled_pattern(over) }
        .to raise_error(ArgumentError, "pattern exceeds #{described_class::MAX_PATTERN_BYTES} bytes")
    end

    it 'counts the byte cap after stripping surrounding slashes' do
      wrapped = "/#{'a' * (described_class::MAX_PATTERN_BYTES + 1)}/"

      expect { described_class.compiled_pattern(wrapped) }
        .to raise_error(ArgumentError, "pattern exceeds #{described_class::MAX_PATTERN_BYTES} bytes")
    end

    it 'accepts a slash-stripped source of exactly the byte cap', :aggregate_failures do
      cap = described_class::MAX_PATTERN_BYTES

      expect(described_class.compiled_pattern('a' * cap)).to be_a(Regexp)
      expect(described_class.compiled_pattern("/#{'a' * cap}/")).to be_a(Regexp)
    end

    it 'counts bytes, not characters', :aggregate_failures do
      pattern = 'é' * 129

      expect(pattern.length).to be <= described_class::MAX_PATTERN_BYTES
      expect(pattern.bytesize).to be > described_class::MAX_PATTERN_BYTES
      expect { described_class.compiled_pattern(pattern) }
        .to raise_error(ArgumentError, "pattern exceeds #{described_class::MAX_PATTERN_BYTES} bytes")
    end
  end
end
