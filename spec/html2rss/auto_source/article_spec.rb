# frozen_string_literal: true

require 'rspec'

RSpec.describe Html2rss::AutoSource::Article do
  subject(:instance) { described_class.new(**options) }

  let(:options) { { title: 'Sample instance', url: 'http://example.com', description: 'By John Doe' } }

  describe '#initialize' do
    it 'stores the options as a hash' do
      expect(instance.instance_variable_get(:@to_h)).to eq(options)
    end

    context 'when unknown options are present' do
      let(:options) { { title: 'Sample instance', url: 'http://example.com', description: 'By John Doe', unknown_key: 'value' } }

      before { allow(Html2rss::Log).to receive(:warn) }

      it 'logs a warning' do
        described_class.new(**options)
        expect(Html2rss::Log).to have_received(:warn).with('Article: unknown keys found: unknown_key')
      end
    end
  end

  describe '#each' do
    let(:yields) do
      described_class::PROVIDED_KEYS.map do |key|
        [key, instance.public_send(key)]
      end
    end

    it 'yields each PROVIDED_KEY with their values' do
      expect { |b| instance.each(&b) }.to yield_successive_args(*yields)
    end
  end

  describe '#url' do
    it 'returns the url if present', :aggregate_failures do
      url = instance.url

      expect(url).to be_a(Addressable::URI)
      expect(url.to_s).to eq('http://example.com/')
    end

    it 'returns nil if no url is present' do
      instance = described_class.new(title: 'Sample instance')
      expect(instance.url).to be_nil
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

  describe '#published_at' do
    it 'returns a Time object if published_at is present and valid' do
      instance = described_class.new(published_at: '2022-01-01T12:00:00Z')
      expect(instance.published_at).to be_a(Time)
    end

    it 'returns nil if published_at is not present' do
      instance = described_class.new
      expect(instance.published_at).to be_nil
    end

    it 'returns nil if published_at is invalid' do
      instance = described_class.new(published_at: 'invalid_date')
      expect(instance.published_at).to be_nil
    end
  end
end
