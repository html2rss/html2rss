# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::PostProcessors::Gsub do
  it { expect(described_class).to be < Html2rss::Selectors::PostProcessors::Base }

  context 'with args validation' do
    context 'without pattern option' do
      it do
        expect do
          described_class.new('hello',
                              options: { replacement: 'world' })
        end.to raise_error(Html2rss::Selectors::PostProcessors::MissingOption,
                           /The `pattern` option is missing in: {/)
      end
    end

    context 'without replacement option' do
      it do
        expect do
          described_class.new('hello',
                              options: { pattern: 'world' })
        end.to raise_error(Html2rss::Selectors::PostProcessors::MissingOption,
                           /The `replacement` option is missing in: {/)
      end
    end

    context 'without replacement option not being a String or Hash' do
      it do
        expect do
          described_class.new('hello', options: { pattern: 'world', replacement: [] })
        end.to raise_error(Html2rss::Selectors::PostProcessors::InvalidType,
                           /The type of `replacement` must be String or Hash, but is: Array in: {/)
      end
    end
  end

  context 'with string pattern' do
    context 'with string replacement' do
      subject do
        described_class.new('Foo bar and boo', options: { pattern: 'boo', replacement: 'baz' }).get
      end

      it { is_expected.to eq 'Foo bar and baz' }
    end
  end

  context 'with pattern being a Regexp as String' do
    context 'with hash replacement' do
      subject do
        described_class.new('hello',
                            options: { pattern: '/[eo]/', replacement: { 'e' => 3, 'o' => '*' } }).get
      end

      it { is_expected.to eq 'h3ll*' }
    end

    context 'with single character string' do
      subject do
        described_class.new('hello',
                            options: { pattern: '/', replacement: 'X' }).get
      end

      it { is_expected.to eq 'hello' }
    end

    context 'with three character string with slashes' do
      subject do
        described_class.new('hello',
                            options: { pattern: '/e/', replacement: 'X' }).get
      end

      it { is_expected.to eq 'hXllo' }
    end
  end
end
