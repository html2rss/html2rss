# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::PostProcessors::Base do
  subject(:instance) { described_class.new(value, context) }

  let(:value) { 'test' }

  describe '.validate_options!' do
    let(:processor) do
      Class.new(described_class) do
        const_set(:OPTIONS, [
          Html2rss::Selectors::Option.new(name: :key1, type: String),
          Html2rss::Selectors::Option.new(name: :key2, type: String, required: false)
        ].freeze)
      end
    end

    it 'does not raise when required options are present and typed' do
      context = Html2rss::Selectors::Context.new(options: { key1: 'value1' })
      expect { processor.validate_options!(context) }.not_to raise_error
    end

    it 'raises when a required option is missing' do
      context = Html2rss::Selectors::Context.new(options: {})
      expect do
        processor.validate_options!(context)
      end.to raise_error(Html2rss::Selectors::PostProcessors::MissingOption,
                         /The `key1` option is missing in:/)
    end

    it 'raises when an optional option has the wrong type' do
      context = Html2rss::Selectors::Context.new(options: { key1: 'ok', key2: 1 })
      expect do
        processor.validate_options!(context)
      end.to raise_error(Html2rss::Selectors::PostProcessors::InvalidType, /type of `key2`/)
    end
  end

  describe '.assert_type' do
    let(:context) { Html2rss::Selectors::Context.new(options: { name: 'gsub' }) }

    it 'does not raise an error if value is of the correct type' do
      expect { described_class.assert_type('string', String, 'test', context:) }.not_to raise_error
    end

    it 'raises an error if value is of the incorrect type' do
      expect do
        described_class.assert_type(123, String, 'test', context:)
      end.to raise_error(Html2rss::Selectors::PostProcessors::InvalidType,
                         /The type of `test` must be String, but is: Integer in: \{.*name.*gsub/)
    end

    it 'supports multiple types', :aggregate_failures do
      expect do
        described_class.assert_type('string', [String, Symbol], 'test', context:)
        described_class.assert_type(:symbol, [String, Symbol], 'test', context:)
      end.not_to raise_error
    end
  end

  describe '.validate_args!' do
    it 'is a no-op by default' do
      expect do
        described_class.validate_args!('', Html2rss::Selectors::Context.new(options: {}))
      end.not_to raise_error
    end
  end

  describe '#initialize' do
    before { allow(described_class).to receive(:validate_args!).with(value, context) }

    let(:value) { 'test' }
    let(:context) { Html2rss::Selectors::Context.new(options: { key1: 'value1' }) }

    it 'calls validate_args! with value and context' do
      described_class.new(value, context)
      expect(described_class).to have_received(:validate_args!).with(value, context)
    end

    it 'rejects legacy hash context' do # rubocop:disable RSpec/ExampleLength
      expect do
        described_class.new(value, { options: { key1: 'value1' } })
      end.to raise_error(
        Html2rss::Selectors::PostProcessors::InvalidType,
        /type of `context` must be Html2rss::Selectors::Context/
      )
    end
  end

  describe '#get' do
    before do
      allow(described_class).to receive_messages(assert_type: nil, validate_options!: nil, validate_args!: nil)
    end

    it 'raises NotImplementedError' do
      expect do
        described_class.new('value',
                            Html2rss::Selectors::Context.new(options: {})).get
      end.to raise_error(NotImplementedError, 'You must implement the `get` method in the post processor')
    end
  end
end
