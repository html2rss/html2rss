# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Configuration do
  after { Html2rss.send(:reset_configuration!) }

  describe 'defaults' do
    subject(:config) { described_class.new }

    it 'has default log_level from ENV or :warn' do
      expected_level = Logger.const_get(ENV.fetch('LOG_LEVEL', :warn).to_s.upcase.to_sym)
      expect(config.log_level).to eq(expected_level)
    end

    it 'has default headers as nil' do
      expect(config.headers).to be_nil
    end

    it 'has default default_strategy as nil' do
      expect(config.default_strategy).to be_nil
    end

    it 'has default min_ttl as nil' do
      expect(config.min_ttl).to be_nil
    end

    it 'has default stylesheets as empty array' do
      expect(config.stylesheets).to eq([])
    end
  end

  describe '#log_level=' do
    subject(:config) { described_class.new }

    it 'accepts valid symbol log levels and updates logger.level', :aggregate_failures do
      config.log_level = :info
      expect(config.log_level).to eq(Logger::INFO)
      expect(config.logger.level).to eq(Logger::INFO)
    end

    it 'accepts valid string log levels', :aggregate_failures do
      config.log_level = 'debug'
      expect(config.log_level).to eq(Logger::DEBUG)
      expect(config.logger.level).to eq(Logger::DEBUG)
    end

    it 'accepts valid integer log levels', :aggregate_failures do
      config.log_level = Logger::ERROR
      expect(config.log_level).to eq(Logger::ERROR)
      expect(config.logger.level).to eq(Logger::ERROR)
    end

    it 'raises ArgumentError for invalid log level' do
      expect { config.log_level = :foo }.to raise_error(ArgumentError, /invalid log level/)
    end

    it 'raises ArgumentError for invalid integer log level' do
      expect { config.log_level = 6 }.to raise_error(ArgumentError, /invalid log level/)
    end
  end

  describe '#headers=' do
    subject(:config) { described_class.new }

    it 'accepts a Hash' do
      config.headers = { 'user-agent' => 'custom' }
      expect(config.headers).to eq({ 'user-agent' => 'custom' })
    end

    it 'accepts a Proc/callable' do
      callable = -> { { 'user-agent' => 'dynamic' } }
      config.headers = callable
      expect(config.headers).to eq(callable)
    end

    it 'raises ArgumentError for invalid headers' do
      expect { config.headers = 'not' }.to raise_error(
        ArgumentError, /headers must be a Hash or respond to #call/
      )
    end

    it 'dups and freezes the assigned Hash', :aggregate_failures do
      headers_hash = { 'user-agent' => 'custom' }
      config.headers = headers_hash
      expect(config.headers).to be_frozen
      headers_hash['user-agent'] = 'mutated'
      expect(config.headers['user-agent']).to eq('custom')
    end
  end

  describe '#default_strategy=' do
    subject(:config) { described_class.new }

    it 'accepts a registered strategy' do
      config.default_strategy = :faraday
      expect(config.default_strategy).to eq(:faraday)
    end

    it 'accepts string and normalizes to symbol' do
      config.default_strategy = 'faraday'
      expect(config.default_strategy).to eq(:faraday)
    end

    it 'accepts nil' do
      config.default_strategy = nil
      expect(config.default_strategy).to be_nil
    end

    it 'raises ArgumentError for unregistered strategy' do
      expect { config.default_strategy = :invalid_strategy }.to raise_error(ArgumentError, /unknown strategy/)
    end

    it 'raises ArgumentError for invalid types', :aggregate_failures do
      expect { config.default_strategy = 123 }
        .to raise_error(ArgumentError, /strategy must be a Symbol or String/)
      expect { config.default_strategy = { strategy: :faraday } }
        .to raise_error(ArgumentError, /strategy must be a Symbol or String/)
    end
  end

  describe '#min_ttl=' do
    subject(:config) { described_class.new }

    it 'accepts positive integer' do
      config.min_ttl = 60
      expect(config.min_ttl).to eq(60)
    end

    it 'accepts numeric string' do
      config.min_ttl = '120'
      expect(config.min_ttl).to eq(120)
    end

    it 'accepts nil' do
      config.min_ttl = nil
      expect(config.min_ttl).to be_nil
    end

    it 'raises ArgumentError for zero or negative numbers', :aggregate_failures do
      expect { config.min_ttl = 0 }.to raise_error(ArgumentError, /must be a positive integer/)
      expect { config.min_ttl = -10 }.to raise_error(ArgumentError, /must be a positive integer/)
    end

    it 'raises ArgumentError for invalid types' do
      expect { config.min_ttl = 'abc' }.to raise_error(ArgumentError, /must be a positive integer/)
    end
  end

  describe '#stylesheets=' do
    subject(:config) { described_class.new }

    it 'accepts an Array of Hashes' do
      stylesheets = [{ href: 'style.css', type: 'text/css' }]
      config.stylesheets = stylesheets
      expect(config.stylesheets).to eq(stylesheets)
    end

    it 'raises ArgumentError if not an Array' do
      expect { config.stylesheets = { href: 'style.css' } }.to raise_error(ArgumentError, /must be an Array/)
    end

    it 'raises ArgumentError if any item in the Array is not a Hash' do
      expect { config.stylesheets = ['style.css'] }.to raise_error(ArgumentError, /must be an Array of Hashes/)
    end

    it 'copies and freezes the array and its hashes', :aggregate_failures do
      sheet = { href: 'style.css', type: 'text/css' }
      config.stylesheets = [sheet]
      expect(config.stylesheets).to be_frozen.and(all(be_frozen))
      sheet[:href] = 'mutated'
      expect(config.stylesheets.first[:href]).to eq('style.css')
    end
  end

  describe 'Html2rss::Log delegation' do
    let(:custom_logger) { instance_double(Logger) }

    before do
      allow(custom_logger).to receive_messages(respond_to?: true, 'level=' => nil, 'formatter=' => nil)
      allow(custom_logger).to receive(:info).with('delegated message')
      Html2rss.configure { |config| config.logger = custom_logger }
    end

    it 'delegates to the active configuration logger' do
      Html2rss::Log.info('delegated message')
      expect(custom_logger).to have_received(:info).with('delegated message')
    end
  end

  describe 'custom duck-typed logger' do
    let(:messages) { [] }
    let(:duck_logger) do
      Class.new do
        attr_accessor :level, :formatter

        def info(msg)
          @messages ||= []
          @messages << msg
        end

        def messages
          @messages ||= []
        end
      end.new
    end

    it 'accepts any object and forwards log levels if supported', :aggregate_failures do
      Html2rss.configure { |c| [c.logger = duck_logger, c.log_level = :info] }

      expect(duck_logger.level).to eq(Logger::INFO)
      Html2rss::Log.info('duck message')
      expect(duck_logger.messages).to eq(['duck message'])
    end

    it 'accepts objects that do not respond to level= or formatter=' do
      simple_logger = Class.new { def info(_msg); end }.new
      expect { Html2rss.configure { |c| c.logger = simple_logger } }.not_to raise_error
    end
  end

  describe 'logger_formatter Proc' do
    let(:log_output) { StringIO.new }
    let(:logger) { Logger.new(log_output) }
    let(:custom_formatter) { proc { |severity, _datetime, _progname, msg| "#{severity} - #{msg}" } }

    before do
      Html2rss.configure do |config|
        config.logger = logger
        config.log_level = :info
        config.logger_formatter = custom_formatter
      end
    end

    it 'formats log messages using the configured Proc', :aggregate_failures do
      Html2rss::Log.info('formatted log')
      expect(log_output.string).to include('INFO - formatted log')
    end
  end

  describe 'invalid logger_formatter' do
    it 'raises ArgumentError if formatter does not respond to call' do
      expect { Html2rss.configure { |c| c.logger_formatter = 'not callable' } }
        .to raise_error(ArgumentError, /formatter must respond to #call/)
    end
  end

  describe 'global configuration integration' do
    context 'when configuring min_ttl and stylesheets' do
      before do
        Html2rss.configure do |config|
          config.min_ttl = 45
          config.stylesheets = [{ href: 'global.css' }]
        end
      end

      it 'freezes the configuration', :aggregate_failures do
        expect(Html2rss.configuration).to be_frozen
        expect(Html2rss.configuration.min_ttl).to eq(45)
        expect(Html2rss.configuration.stylesheets).to eq([{ href: 'global.css' }])
      end
    end

    context 'when evaluating RCU behavior' do
      let!(:initial_config) { Html2rss.configuration }

      before do
        Html2rss.configure do |config|
          config.min_ttl = 15
        end
      end

      it 'is thread-safe and implements RCU duplicate/freeze', :aggregate_failures do
        expect(initial_config).to be_frozen
        expect(Html2rss.configuration).to be_frozen
        expect(Html2rss.configuration).not_to eq(initial_config)
      end
    end

    it 'raises FrozenError when trying to modify configuration directly' do
      expect { Html2rss.configuration.min_ttl = 15 }.to raise_error(FrozenError)
    end

    context 'with global static headers' do
      before do
        Html2rss.configure do |config|
          config.headers = {
            'user-agent' => 'GlobalUA',
            'X-Custom-Header' => 'CustomValue'
          }
        end
      end

      it 'merges global static headers and normalizes keys', :aggregate_failures do
        defaults = Html2rss::Config::RequestHeaders.browser_defaults
        expect(defaults['User-Agent']).to eq('GlobalUA')
        expect(defaults['X-Custom-Header']).to eq('CustomValue')
      end
    end

    context 'with dynamic headers' do
      let(:counter) { { count: 0 } }

      before do
        cnt = counter
        Html2rss.configure do |config|
          config.headers = -> { { 'x-count' => (cnt[:count] += 1).to_s } }
        end
      end

      it 'evaluates dynamic headers and increments count', :aggregate_failures do
        expect(Html2rss::Config::RequestHeaders.browser_defaults['X-Count']).to eq('1')
        expect(Html2rss::Config::RequestHeaders.browser_defaults['X-Count']).to eq('2')
      end
    end

    describe 'integration with ClassMethods' do
      before do
        Html2rss.configure do |config|
          config.default_strategy = :faraday
        end
      end

      it 'uses global default strategy when strategy in config is default_strategy_name', :aggregate_failures do
        expect(Html2rss::Config.default_strategy_name).to eq(:faraday)
        expect(Html2rss::Config.default_config[:strategy]).to eq(:faraday)
      end

      it 'uses global stylesheets in default_config' do
        global_stylesheets = [{ href: 'global.css', type: 'text/css' }]
        Html2rss.configure { |config| config.stylesheets = global_stylesheets }

        expect(Html2rss::Config.default_config[:stylesheets]).to eq(global_stylesheets)
      end
    end

    describe 'integration with RssBuilder::Channel#ttl' do
      let(:response) do
        instance_double(
          Html2rss::RequestService::Response,
          url: 'http://example.com',
          headers: { 'cache-control' => 'max-age=1800' }, # 30 minutes
          html_response?: false,
          parsed_body: nil
        )
      end

      it 'enforces min_ttl as a strict lower bound' do
        Html2rss.configure { |config| config.min_ttl = 60 }

        channel = Html2rss::RssBuilder::Channel.new(response)
        expect(channel.ttl).to eq(60) # 30 mins clamped to min_ttl (60)
      end

      it 'does not clamp if computed ttl is larger than min_ttl' do
        Html2rss.configure { |config| config.min_ttl = 15 }

        channel = Html2rss::RssBuilder::Channel.new(response)
        expect(channel.ttl).to eq(30) # 30 mins is > 15, so unchanged
      end

      it 'clamps config overrides for ttl as well' do
        Html2rss.configure { |config| config.min_ttl = 60 }

        channel = Html2rss::RssBuilder::Channel.new(response, overrides: { ttl: 20 })
        expect(channel.ttl).to eq(60) # override 20 clamped to min_ttl (60)
      end
    end
  end
end
