# frozen_string_literal: true

require 'rspec'

RSpec.describe Html2rss::AutoSource::Article do
  subject(:instance) { described_class.new(**options) }

  let(:options) { { title: 'Sample instance', url: 'http://example.com', author: 'John Doe' } }

  describe '#initialize' do
    it 'stores the options as a hash' do
      expect(instance.instance_variable_get(:@to_h)).to eq(options)
    end
  end

  describe '#[]' do
    it 'retrieves the value for a given key' do
      expect(instance[:title]).to eq('Sample instance')
    end
  end

  describe '#[]=' do
    it 'sets the value for a given key' do
      instance[:title] = 'New Title'
      expect(instance[:title]).to eq('New Title')
    end
  end

  describe '#keys' do
    it 'returns the keys of the hash' do
      expect(instance.keys).to contain_exactly(:title, :url, :author)
    end
  end

  describe '#each' do
    it 'iterates over each key-value pair' do
      expect do |b|
        instance.each(&b)
      end.to yield_successive_args([:title, 'Sample instance'], [:url, 'http://example.com'],
                                   [:author, 'John Doe'])
    end
  end

  describe '#url' do
    it 'returns the url if present' do
      expect(instance.url).to eq('http://example.com')
    end

    it 'returns nil if no url is present' do
      instance = described_class.new(title: 'Sample instance')
      expect(instance.url).to be_nil
    end
  end

  describe '#respond_to_missing?' do
    it 'returns true if the method name is a key in the hash' do
      expect(instance.respond_to?(:title)).to be true
    end

    it 'returns false if the method name is not a key in the hash' do
      expect(instance.respond_to?(:nonexistent)).to be false
    end
  end

  describe '#method_missing' do
    it 'returns the value for a given key if it exists' do
      expect(instance.title).to eq('Sample instance')
    end

    it 'raises NoMethodError if the key does not exist' do
      expect { instance.nonexistent }.to raise_error(NoMethodError)
    end
  end

  describe '#valid?' do
    context 'when url, title, and id are present' do
      let(:options) { { url: 'http://example.com', title: 'Sample Title', id: 'foobar' } }

      it { is_expected.to be_valid }
    end

    context 'when url is missing' do
      let(:options) { { title: 'Sample Title' } }

      it { is_expected.not_to be_valid }
    end

    context 'when title is missing' do
      let(:options) { { url: 'http://example.com' } }

      it { is_expected.not_to be_valid }
    end

    context 'when url, title, and guid are missing' do
      let(:options) { {} }

      it { is_expected.not_to be_valid }
    end
  end
end
