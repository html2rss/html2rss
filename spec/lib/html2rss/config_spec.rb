# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Config do
  describe Html2rss::Config::MultipleFeedsConfig do
    describe '::CONFIG_KEY_FEEDS' do
      it { expect(described_class::CONFIG_KEY_FEEDS).to eq :feeds }
    end
  end

  describe '.load_yaml' do
    context 'when the file does not exist' do
      let(:file) { 'non-existing-file' }

      it 'raises an ArgumentError' do
        expect do
          described_class.load_yaml(file)
        end.to raise_error(ArgumentError,
                           "File 'non-existing-file' does not exist")
      end
    end

    context 'when the file exists & the feed name is reserved' do
      let(:file) { 'spec/fixtures/feeds.test.yml' }

      it 'raises an ArgumentError' do
        expect do
          described_class.load_yaml(file,
                                    described_class::MultipleFeedsConfig::CONFIG_KEY_FEEDS)
        end.to raise_error(ArgumentError,
                           "`#{described_class::MultipleFeedsConfig::CONFIG_KEY_FEEDS}` is a reserved feed name")
      end
    end

    context 'when the file exists & is single config' do
      let(:file) { 'spec/fixtures/single.test.yml' }

      it 'raises an ArgumentError' do
        expect(described_class.load_yaml(file)).to be_a(Hash)
      end
    end

    context 'when the file exists with multiple feeds & the feed name is not found' do
      let(:file) { 'spec/fixtures/feeds.test.yml' }

      it 'raises an ArgumentError' do
        expect do
          described_class.load_yaml(file,
                                    'non-existing-feed')
        end.to raise_error(ArgumentError, /Feed 'non-existing-feed' not found under `feeds` key/)
      end
    end

    context 'when the file exists with multiple feeds & the feed name is found' do
      let(:file) { 'spec/fixtures/feeds.test.yml' }

      let(:expected_config) do
        {
          headers: { 'User-Agent': String, 'Content-Language': 'en' },
          stylesheets: [{ href: '/style.xls', media: 'all', type: 'text/xsl' },
                        { href: '/rss.css', media: 'all', type: 'text/css' },
                        { href: '/special.css', type: 'text/css' }],
          channel: { language: 'en', url: String },
          selectors: { description: { selector: 'p' }, items: { selector: 'div.main-horoscope' },
                       link: { extractor: 'href', selector: '#src-horo-today' } }
        }
      end

      it 'returns the configuration' do
        expect(described_class.load_yaml(file, 'notitle')).to match(expected_config)
      end
    end
  end

  describe '.from_hash' do
    let(:hash) do
      {
        headers: { 'User-Agent': 'Agent-User', 'Content-Language': 'en' },
        stylesheets: [{ href: '/style.xls', media: 'all', type: 'text/xsl' },
                      { href: '/rss.css', media: 'all', type: 'text/css' },
                      { href: '/special.css', type: 'text/css' }],
        channel: { language: 'en', url: 'http://example.com' },
        selectors: { description: { selector: 'p' }, items: { selector: 'div.main-horoscope' },
                     link: { extractor: 'href', selector: '#src-horo-today' } }
      }
    end

    it 'returns the configuration' do
      expect(described_class.from_hash(hash)).to be_a(described_class)
    end
  end

  describe '#initialize' do
    subject(:instance) { described_class.new(config) }

    let(:config) do
      {
        headers: { 'User-Agent': 'Agent-User', 'Content-Language': 'en' },
        stylesheets: [{ href: '/style.xls', media: 'all', type: 'text/xsl' },
                      { href: '/rss.css', media: 'all', type: 'text/css' },
                      { href: '/special.css', type: 'text/css' }],
        channel: { language: 'en', url: 'http://example.com' },
        selectors: { description: { selector: 'p' }, items: { selector: 'div.main-horoscope' },
                     link: { extractor: 'href', selector: '#src-horo-today' } }
      }
    end

    it 'inits' do
      expect { instance }.not_to raise_error
    end

    it 'applies default configuration' do
      expect(instance.time_zone).to eq('UTC')
    end

    it 'deep merges with the default configuration' do
      expect(instance.url).to eq('http://example.com')
    end

    context 'when the configuration is invalid' do
      let(:config) { { headers: { 'User-Agent': nil, 'Content-Language': 0xBADF00D } } }

      it 'raises an ArgumentError' do
        expect { instance }.to raise_error(ArgumentError, /Invalid configuration:/)
      end
    end

    context 'when configuration uses deprecated channel attributes' do
      before do
        allow(Html2rss::Log).to receive(:warn).and_return(nil)
      end

      let(:config) do
        {
          channel: { url: 'https://example.com',
                     headers: { 'User-Agent': 'Agent-User', 'Content-Language': 'en' },
                     strategy: :browserless },
          auto_source: {}
        }
      end

      %i[strategy headers].each do |key|
        it "warns about deprecated #{key}" do
          instance
          expect(Html2rss::Log).to have_received(:warn).with(/`channel.#{key}` key is deprecated./)
        end

        it "moves deprecated #{key} to top level" do
          expect(instance.public_send(key)).to eq(config.dig(:channel, key))
        end
      end
    end
  end
end
