# frozen_string_literal: true

RSpec.describe Html2rss::Config::Channel do
  describe '.required_params_for_config(config)' do
    it do
      expect(
        described_class.required_params_for_config(
          { url: 'http://example.com/%<section>s/%<something>d' }
        )
      ).to be_a(Set).and include 'section', 'something'
    end
  end

  describe '#url' do
    subject { described_class.new(hash, params:).url }

    let(:params) { {} }

    context 'with non-ascii url and without dynamic parameters' do
      let(:hash) do
        { url: 'https://例子.測試/23/' }
      end

      it do
        expect(subject).to eq Addressable::URI.parse('https://例子.測試/23/')
      end
    end

    context 'with non-ascii url and with dynamic parameters' do
      let(:hash) do
        { url: 'https://例子.測試/%<id>s/' }
      end

      let(:params) { { id: 42 } }

      it do
        expect(subject).to eq Addressable::URI.parse('https://例子.測試/42/')
      end
    end
  end

  describe '#strategy' do
    context 'without channel strategy' do
      subject { described_class.new({ url: '' }).strategy }

      it { is_expected.to eq :faraday }
    end

    context 'with channel strategy' do
      subject { described_class.new({ url: '', strategy: 'browserless' }).strategy }

      it { is_expected.to eq :browserless }
    end
  end
end
