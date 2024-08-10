# frozen_string_literal: true

RSpec.describe Html2rss::AttributePostProcessors::Gsub do
  it { expect(described_class).to be < Html2rss::AttributePostProcessors::Base }

  context 'with args validation' do
    context 'without pattern option' do
      it do
        expect do
          described_class.new('hello',
                              options: { replacement: 'world' })
        end.to raise_error(Html2rss::AttributePostProcessors::MissingOption,
                           'The `pattern` option is missing in: {:replacement=>"world"}')
      end
    end

    context 'without replacement option' do
      it do
        expect do
          described_class.new('hello',
                              options: { pattern: 'world' })
        end.to raise_error(Html2rss::AttributePostProcessors::MissingOption,
                           'The `replacement` option is missing in: {:pattern=>"world"}')
      end
    end

    context 'without replacement option not being a String or Hash' do
      it do
        expect do
          described_class.new('hello', options: { pattern: 'world', replacement: [] })
        end.to raise_error(Html2rss::AttributePostProcessors::InvalidType,
                           'The type of `replacement` must be String or Hash, but is: ' \
                           'Array in: {:pattern=>"world", :replacement=>[]}')
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
  end
end
