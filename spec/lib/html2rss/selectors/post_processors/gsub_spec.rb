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
end
