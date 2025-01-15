# frozen_string_literal: true

RSpec.describe Html2rss::Scrapers::AttributePostProcessors::Base do
  subject(:instance) { described_class.new(value, context) }

  let(:value) { 'test' }

  describe '.expect_options' do
    let(:context) { Html2rss::Scrapers::Selectors::Context.new({ options: { key1: 'value1', key2: 'value2' } }) }

    it 'does not raise an error if all keys are present' do
      expect { described_class.send(:expect_options, %i[key1 key2], context) }.not_to raise_error
    end

    it 'raises an error if a key is missing' do
      expect do
        described_class.send(:expect_options, %i[key1 key3], context)
      end.to raise_error(Html2rss::Scrapers::AttributePostProcessors::MissingOption, /The `key3` option is missing in:/)
    end
  end

  describe '.assert_type' do
    let(:context) { nil }

    it 'does not raise an error if value is of the correct type' do
      expect { described_class.send(:assert_type, 'string', String, 'test', context:) }.not_to raise_error
    end

    it 'raises an error if value is of the incorrect type' do
      expect do
        described_class.send(:assert_type, 123, String, 'test', context:)
      end.to raise_error(Html2rss::Scrapers::AttributePostProcessors::InvalidType,
                         /The type of `test` must be String, but is: Integer in: {.*"base_spec.rb"}/)
    end

    it 'supports multiple types', :aggregate_failures do
      expect do
        described_class.send(:assert_type, 'string', [String, Symbol], 'test', context:)
        described_class.send(:assert_type, :symbol, [String, Symbol], 'test', context:)
      end.not_to raise_error
    end
  end

  describe '.validate_args!' do
    it 'raises NotImplementedError' do
      expect do
        described_class.send(:validate_args!, '', Html2rss::Scrapers::Selectors::Context.new({}))
      end.to raise_error(NotImplementedError, 'You must implement the `validate_args!` method in the post processor')
    end
  end

  describe '#initialize' do
    before { allow(described_class).to receive(:validate_args!).with(value, context) }

    let(:value) { 'test' }
    let(:context) { Html2rss::Scrapers::Selectors::Context.new({ options: { key1: 'value1' } }) }

    it 'calls validate_args! with value and context' do
      described_class.new(value, context)
      expect(described_class).to have_received(:validate_args!).with(value, context)
    end
  end

  describe '#get' do
    before do
      allow(described_class).to receive_messages(assert_type: nil, validate_args!: nil)
    end

    it 'raises NotImplementedError' do
      expect do
        described_class.new('value',
                            Html2rss::Scrapers::Selectors::Context.new({ options: {} })).get
      end.to raise_error(NotImplementedError, 'You must implement the `get` method in the post processor')
    end
  end
end
