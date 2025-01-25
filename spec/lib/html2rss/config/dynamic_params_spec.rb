# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Config::DynamicParams do
  describe '.call' do
    let(:params) { { 'name' => 'John', 'age' => '30' } }

    context 'when value is a String' do
      it 'replaces format string with given params' do
        value = 'Hello, %<name>s. You are %<age>s years old.'
        result = described_class.call(value, params)
        expect(result).to eq('Hello, John. You are 30 years old.')
      end
    end

    context 'when value is a Hash' do
      it 'replaces format string with given params recursively' do
        value = { greeting: 'Hello, %<name>s.', details: { age: 'You are %<age>s years old.' } }
        result = described_class.call(value, params)
        expect(result).to eq({ greeting: 'Hello, John.', details: { age: 'You are 30 years old.' } })
      end
    end

    context 'when value is an Array' do
      it 'replaces format string with given params recursively' do
        value = ['Hello, %<name>s.', 'You are %<age>s years old.']
        result = described_class.call(value, params)
        expect(result).to eq(['Hello, John.', 'You are 30 years old.'])
      end
    end

    context 'when value is an Object' do
      it 'returns the value as is' do
        value = 42
        result = described_class.call(value, params)
        expect(result).to eq(42)
      end
    end

    context 'with getter' do
      let(:getter) { ->(key) { "Mr. #{key.capitalize}" } }

      it 'replaces format string with given params and getter' do
        value = 'Hello, %<name>s. You are %<age>s years old.'
        result = described_class.call(value, params, getter: getter)
        expect(result).to eq('Hello, Mr. Name. You are Mr. Age years old.')
      end
    end

    context 'with "%<foo>d : %<bar>f" template format' do
      it 'replaces format string with given params' do
        value = '%<foo>d : %<bar>f'
        result = described_class.call(value, { foo: 1, bar: 2.0 })
        expect(result).to eq('1 : 2.000000')
      end
    end

    context 'with replace_missing_with being a String' do
      it 'replaces missing params with the given value' do
        value = 'Hello, %<name>s. You are %<age>s years old. Your city is %<city>s.'
        result = described_class.call(value, params, replace_missing_with: 'unknown')
        expect(result).to eq('Hello, John. You are 30 years old. Your city is unknown.')
      end
    end

    context 'with replace_missing_with being nil' do
      it 'raises ParamsMissing error when a param is missing' do
        value = 'Hello, %<name>s. You are %<age>s years old. Your city is %<city>s.'
        expect do
          described_class.call(value, params)
        end.to raise_error(described_class::ParamsMissing)
      end
    end
  end
end
