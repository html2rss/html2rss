# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Config do
  it { expect(described_class::InvalidConfig).to be < Html2rss::Error }

  describe Html2rss::Config::MultipleFeedsConfig do
    describe '::CONFIG_KEY_FEEDS' do
      it { expect(described_class::CONFIG_KEY_FEEDS).to eq :feeds }
    end

    describe '.to_single_feed' do
      let(:yaml) do
        {
          channel: { language: 'en', metadata: { site: 'global' } },
          headers: { 'User-Agent': 'Global Agent' },
          stylesheets: [{ href: '/global.css', type: 'text/css' }],
          strategy: :faraday,
          feeds: {
            sample: {
              channel: { metadata: { section: 'local' } },
              headers: { 'X-Feed': 'sample' },
              stylesheets: [{ href: '/local.css', type: 'text/css' }],
              strategy: :browserless
            }
          }
        }
      end

      let(:expected_merged) do
        {
          channel: { language: 'en', metadata: { site: 'global', section: 'local' } },
          headers: { 'User-Agent': 'Global Agent', 'X-Feed': 'sample' },
          stylesheets: [{ href: '/global.css', type: 'text/css' }, { href: '/local.css', type: 'text/css' }],
          strategy: :browserless
        }
      end

      it 'deep merges nested hash values and keeps local scalar overrides' do
        merged = described_class.to_single_feed(yaml[:feeds][:sample].dup, yaml)
        expect(merged).to include(expected_merged)
      end
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

    context 'when the file exists with multiple feeds & the feed name is omitted' do
      let(:file) { 'spec/fixtures/feeds.test.yml' }

      it 'raises an ArgumentError listing the available feeds' do
        expect { described_class.load_yaml(file) }
          .to raise_error(ArgumentError, /Feed name is required under `feeds`\. Available feeds:/)
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

    it 'defaults strategy to auto when omitted' do
      expect(described_class.from_hash(hash).strategy).to eq(:auto)
    end

    context 'with string-keyed config input' do
      let(:hash) do
        {
          'channel' => { 'url' => 'http://example.com' },
          'selectors' => {
            'items' => { 'selector' => '.item' },
            'title' => { 'selector' => 'h2' }
          }
        }
      end

      it 'normalizes keys at ingress and builds the config' do
        expect(described_class.from_hash(hash)).to be_a(described_class)
      end
    end

    context 'with frozen hash' do
      it 'returns the configuration' do
        expect(described_class.from_hash(hash.freeze)).to be_a(described_class)
      end
    end

    context 'with parameter defaults' do
      let(:hash) do
        {
          parameters: {
            query: { type: 'string', default: 'ruby' },
            locale: { type: 'string', default: 'en' }
          },
          headers: { 'X-Query': '%<query>s' },
          channel: { url: 'https://example.com/search?q=%<query>s&locale=%<locale>s' },
          selectors: {
            items: { selector: '.item' },
            title: { selector: 'h2' }
          }
        }
      end

      it 'applies parameter defaults when params are omitted', :aggregate_failures do
        config = described_class.from_hash(hash)

        expect(config.url).to eq('https://example.com/search?q=ruby&locale=en')
        expect(config.headers).to include('X-Query' => 'ruby')
      end
    end

    it 'tracks omitted request budgets as non-explicit' do # rubocop:disable RSpec/ExampleLength
      config = described_class.from_hash({
                                           channel: { url: 'https://example.com' },
                                           selectors: {
                                             items: { selector: '.item' },
                                             title: { selector: 'h2' }
                                           }
                                         })

      expect(config.request_controls.explicit?(:max_requests)).to be(false)
    end

    it 'tracks explicit request budgets as explicit' do # rubocop:disable RSpec/ExampleLength
      config = described_class.from_hash({
                                           request: { max_requests: 4 },
                                           channel: { url: 'https://example.com' },
                                           selectors: {
                                             items: { selector: '.item' },
                                             title: { selector: 'h2' }
                                           }
                                         })

      expect(config.request_controls.explicit?(:max_requests)).to be(true)
    end
  end

  describe '.auto_source_config' do
    let(:config) do
      described_class.auto_source_config(
        url: 'https://example.com/blog',
        items_selector: '.post',
        request_controls: Html2rss::RequestControls.new(
          strategy: :browserless,
          max_redirects: 8,
          max_requests: 5,
          explicit_keys: %i[strategy max_redirects max_requests]
        )
      )
    end

    it 'builds a top-level auto-source feed config', :aggregate_failures do
      expect(config[:strategy]).to eq(:browserless)
      expect(config[:request]).to eq(max_redirects: 8, max_requests: 5)
      expect(config.dig(:channel, :url)).to eq('https://example.com/blog')
      expect(config[:auto_source]).to eq(Html2rss::AutoSource::DEFAULT_CONFIG)
      expect(config[:selectors]).to eq(items: { selector: '.post', enhance: true })
    end

    it 'leaves optional request overrides unset so runtime config can apply defaults', :aggregate_failures do
      config = described_class.auto_source_config(url: 'https://example.com/blog')

      expect(config).not_to have_key(:request)
      expect(config[:selectors]).to be_nil
    end
  end

  describe '.validate' do
    let(:config) do
      {
        channel: { url: 'http://example.com' },
        selectors: {
          items: { selector: '.item' },
          title: { selector: 'h2' },
          guid: ['title']
        }
      }
    end

    it 'returns a successful validation result for valid config' do
      expect(described_class.validate(config)).to be_success
    end

    it 'applies runtime defaults before validation' do
      result = described_class.validate(config)

      expect(result.to_h.dig(:channel, :time_zone)).to eq('UTC')
    end

    it 'accepts configs when strategy is omitted' do
      config_without_strategy = config.dup

      expect(described_class.validate(config_without_strategy)).to be_success
    end

    it 'rejects unknown strategy values' do
      config_with_unknown_strategy = config.merge(strategy: :unknown)

      expect(described_class.validate(config_with_unknown_strategy)).to be_failure
    end

    it 'accepts strategies registered after validator class load' do # rubocop:disable RSpec/ExampleLength
      described_class.validate(config)
      Html2rss::RequestService.register_strategy(:runtime_custom, Class.new)

      result = described_class.validate(config.merge(strategy: :runtime_custom))
      expect(result).to be_success
    ensure
      Html2rss::RequestService.unregister_strategy(:runtime_custom)
    end

    context 'when request includes valid botasaurus options' do
      let(:config) do
        {
          channel: { url: 'http://example.com' },
          selectors: { items: { selector: '.item' }, title: { selector: 'h2' } },
          request: {
            botasaurus: {
              navigation_mode: 'google_get_bypass',
              max_retries: 3,
              wait_for_selector: '.main',
              wait_timeout_seconds: 15,
              block_images: true,
              block_images_and_css: false,
              wait_for_complete_page_load: true,
              headless: false,
              proxy: 'http://user:pass@proxy:8080',
              user_agent: 'Mozilla/5.0',
              window_size: [1920, 1080],
              lang: 'en-US'
            }
          }
        }
      end

      it 'accepts the botasaurus config contract', :aggregate_failures do
        result = described_class.validate(config)

        expect(result).to be_success
        expect(result.to_h.dig(:request, :botasaurus, :navigation_mode)).to eq('google_get_bypass')
      end
    end

    context 'when request includes invalid botasaurus options' do
      let(:config) do
        {
          channel: { url: 'http://example.com' },
          selectors: { items: { selector: '.item' }, title: { selector: 'h2' } },
          request: {
            botasaurus: {
              navigation_mode: 'invalid_mode',
              max_retries: 4,
              wait_timeout_seconds: 0
            }
          }
        }
      end

      it 'rejects values outside the contract' do
        expect(described_class.validate(config)).to be_failure
      end
    end

    context 'when botasaurus window_size length is not exactly two items' do
      let(:config) do
        {
          channel: { url: 'http://example.com' },
          selectors: { items: { selector: '.item' }, title: { selector: 'h2' } },
          request: {
            botasaurus: {
              window_size: [1920]
            }
          }
        }
      end

      it 'rejects the botasaurus config' do
        expect(described_class.validate(config)).to be_failure
      end
    end

    it 'fails when guid references an unknown selector' do
      config[:selectors][:guid] = ['missing']

      expect(described_class.validate(config)).to be_failure
    end

    it 'does not mutate the caller config hash' do
      original_config = Marshal.load(Marshal.dump(config))

      described_class.validate(config)

      expect(config).to eq(original_config)
    end

    context 'with parameter defaults' do
      let(:config) do
        {
          parameters: {
            query: { type: 'string', default: 'ruby' },
            locale: { type: 'string', default: 'en' }
          },
          headers: { 'X-Query': '%<query>s' },
          channel: { url: 'https://example.com/search?q=%<query>s&locale=%<locale>s' },
          selectors: {
            items: { selector: '.item' },
            title: { selector: 'h2' }
          }
        }
      end

      it 'validates the effective config after applying parameter defaults', :aggregate_failures do
        result = described_class.validate(config)

        expect(result).to be_success
        expect(result.to_h.dig(:channel, :url)).to eq('https://example.com/search?q=ruby&locale=en')
        expect(result.to_h.dig(:headers, :'X-Query')).to eq('ruby')
      end

      it 'resolves the same url and headers as runtime config building', :aggregate_failures do
        result = described_class.validate(config)
        runtime_config = described_class.from_hash(config)

        expect(result.to_h.dig(:channel, :url)).to eq(runtime_config.url)
        expect(result.to_h.dig(:headers, :'X-Query')).to eq(runtime_config.headers.fetch('X-Query'))
      end
    end

    context 'with unresolved placeholders and no defaults' do
      let(:config) do
        {
          parameters: {
            query: { type: 'string' }
          },
          headers: { 'X-Query': '%<query>s' },
          channel: { url: 'https://example.com/search?q=%<query>s' },
          selectors: {
            items: { selector: '.item' },
            title: { selector: 'h2' }
          }
        }
      end

      it 'fails validation with the dynamic params error', :aggregate_failures do
        result = described_class.validate(config)

        expect(result).to be_failure
        expect(result.errors.to_h.fetch(nil)).to include('Missing parameter for formatting: key<query> not found')
      end
    end
  end

  describe '.validate_yaml' do
    it 'validates a YAML config file' do
      expect(described_class.validate_yaml('spec/fixtures/single.test.yml')).to be_success
    end

    it 'validates a parameterized YAML config file using parameter defaults' do
      expect(described_class.validate_yaml('spec/fixtures/parameterized.test.yml')).to be_success
    end

    it 'fails a parameterized YAML config file when placeholders remain unresolved' do
      expect(described_class.validate_yaml('spec/fixtures/parameterized_missing_default.test.yml')).to be_failure
    end
  end

  describe '#initialize' do
    subject(:instance) { described_class.new(config) }

    context 'when the configuration is valid' do
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

      it 'leaves out auto_source' do
        expect(instance.auto_source).to be_nil
      end

      it 'applies default configuration' do
        expect(instance.time_zone).to eq('UTC')
      end

      it 'deep merges with the default configuration' do
        expect(instance.url).to eq('http://example.com')
      end

      it 'freezes @config ivar' do
        expect(instance.instance_variable_get(:@config)).to be_frozen
      end
    end

    context 'when the configuration is valid with auto_source' do
      let(:config) do
        {
          channel: { url: 'http://example.com' },
          auto_source: {
            scraper: {
              schema: { enabled: false },
              html: { minimum_selector_frequency: 3 }
            }
          }
        }
      end

      let(:expected_auto_source_config) do
        {
          scraper: {
            semantic_html: { enabled: true }, # wasn't explicitly set -> default
            schema: { enabled: false },       # keeps the value from the config
            html: {
              enabled: true,
              minimum_selector_frequency: 3,  # was explicitly set -> overrides default
              use_top_selectors: 5            # wasn't explicitly set -> default
            },
            json_state: { enabled: true },    # wasn't explicitly set -> default
            microdata: { enabled: true },     # wasn't explicitly set -> default
            wordpress_api: { enabled: true } # wasn't explicitly set -> default
          },
          cleanup: {
            keep_different_domain: false,     # wasn't explicitly set -> default
            min_words_title: 3                # wasn't explicitly set -> default
          }
        }
      end

      it 'applies default auto_source configuration' do
        expect(instance.auto_source).to eq(expected_auto_source_config)
      end
    end

    context 'when the configuration is invalid' do
      let(:config) { { headers: { 'User-Agent': nil, 'Content-Language': 0xBADF00D } } }

      it 'raises an ArgumentError' do
        expect { instance }.to raise_error(described_class::InvalidConfig, /Invalid configuration:/)
      end
    end

    context 'when configuration includes browserless preload options' do
      let(:config) do
        {
          channel: { url: 'http://example.com' },
          selectors: { items: { selector: 'article' } },
          request: {
            browserless: {
              preload: {
                wait_after_ms: 2_000,
                click_selectors: [
                  { selector: '.load-more', max_clicks: 2, wait_after_ms: 100 }
                ],
                scroll_down: {
                  iterations: 4,
                  wait_after_ms: 1_000
                }
              }
            }
          }
        }
      end

      it 'exposes the request options', :aggregate_failures do
        expect(instance.request.dig(:browserless, :preload, :wait_after_ms)).to eq(2_000)
        expect(instance.request.dig(:browserless, :preload, :click_selectors).first[:max_clicks]).to eq(2)
      end
    end

    context 'when browserless preload configuration is invalid' do
      let(:config) do
        {
          channel: { url: 'http://example.com' },
          selectors: { items: { selector: 'article' } },
          request: {
            browserless: {
              preload: {
                click_selectors: [
                  { selector: '.load-more', max_clicks: 0 }
                ]
              }
            }
          }
        }
      end

      it 'raises an InvalidConfig error' do
        expect { instance }.to raise_error(described_class::InvalidConfig, /max_clicks/)
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
          value = config.dig(:channel, key)
          matcher = key == :headers ? include(value.transform_keys(&:to_s)) : eq(value)

          expect(instance.public_send(key)).to matcher
        end
      end
    end
  end

  describe '#headers' do
    subject(:headers) { described_class.new(config).headers }

    let(:config) do
      {
        channel: { url: 'https://example.com/articles', language: channel_language },
        selectors: { items: { selector: '.item' } },
        headers: custom_headers
      }
    end

    let(:custom_headers) { { 'accept' => 'application/json', 'x-custom-id' => '123' } }
    let(:channel_language) { 'fr' }
    let(:expected_headers) do
      {
        'Host' => 'example.com',
        'Accept-Language' => 'fr',
        'X-Custom-Id' => '123',
        'Accept' => "application/json,#{Html2rss::Config::RequestHeaders::DEFAULT_ACCEPT}"
      }
    end

    it 'normalizes caller provided headers and adds defaults' do
      expect(headers).to include(expected_headers)
    end

    context 'when the channel language is missing' do
      let(:channel_language) { nil }

      it 'falls back to en-US for Accept-Language' do
        expect(headers).to include('Accept-Language' => 'en-US,en;q=0.9')
      end
    end
  end
end
