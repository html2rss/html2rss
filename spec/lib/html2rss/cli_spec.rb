# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Html2rss::CLI do
  subject(:cli) { described_class.new }

  describe '#feed' do
    let(:rss_xml) { '<rss><channel><title>Example</title></channel></rss>' }

    before do
      allow(Html2rss).to receive(:feed).and_return(rss_xml)
    end

    it 'parses the YAML file and prints the RSS feed to stdout' do
      allow(Html2rss).to receive(:config_from_yaml_file).and_return({ url: 'https://example.com' })

      expect { cli.feed('example.yml') }.to output("#{rss_xml}\n").to_stdout
    end

    it 'passes the feed_name to config_from_yaml_file' do
      allow(Html2rss).to receive(:config_from_yaml_file).with('example.yml',
                                                              'feed_name').and_return({ url: 'https://example.com' })

      expect { cli.feed('example.yml', 'feed_name') }.to output("#{rss_xml}\n").to_stdout
    end

    it 'passes the strategy option to the config' do
      allow(Html2rss).to receive(:config_from_yaml_file).and_return({})

      cli.invoke(:feed, ['example.yml'], { strategy: 'browserless' })

      expect(Html2rss).to have_received(:feed).with(hash_including(strategy: :browserless))
    end

    it 'passes the max_redirects option to the config' do
      allow(Html2rss).to receive(:config_from_yaml_file).and_return({})

      cli.invoke(:feed, ['example.yml'], { max_redirects: 8 })

      expect(Html2rss).to have_received(:feed).with(hash_including(request: hash_including(max_redirects: 8)))
    end

    it 'passes the max_requests option to the config' do
      allow(Html2rss).to receive(:config_from_yaml_file).and_return({})

      cli.invoke(:feed, ['example.yml'], { max_requests: 8 })

      expect(Html2rss).to have_received(:feed).with(hash_including(request: hash_including(max_requests: 8)))
    end

    it 'passes the params option to the config' do
      allow(Html2rss).to receive(:config_from_yaml_file).and_return({})

      cli.invoke(:feed, ['example.yml'], { params: { 'foo' => 'bar' } })

      expect(Html2rss).to have_received(:feed).with(hash_including(params: { 'foo' => 'bar' }))
    end

    it 'applies CLI defaults when the YAML config uses nil request overrides' do # rubocop:disable RSpec/ExampleLength
      allow(Html2rss).to receive(:config_from_yaml_file).and_return(
        strategy: nil,
        request: {
          max_redirects: nil,
          max_requests: nil
        }
      )

      cli.feed('example.yml')

      expect(Html2rss).to have_received(:feed).with(
        hash_excluding(:strategy, :request)
      )
    end

    it 'preserves omitted request controls so downstream config can infer budgets' do
      allow(Html2rss).to receive(:config_from_yaml_file).and_return({})

      cli.feed('example.yml')

      expect(Html2rss).to have_received(:feed).with(hash_excluding(:request))
    end
  end

  describe '#auto' do
    let(:auto_rss_xml) { '<rss><channel><title>Auto Source</title></channel></rss>' }
    let(:auto_json_feed) { { version: 'https://jsonfeed.org/version/1.1', title: 'Auto Source', items: [] } }

    before do
      allow(Html2rss).to receive_messages(auto_source: auto_rss_xml, auto_json_feed:)
    end

    it 'calls Html2rss.auto_source and prints the result to stdout' do
      expect { cli.auto('https://example.com') }.to output("#{auto_rss_xml}\n").to_stdout
    end

    it 'passes the strategy option to Html2rss.auto_source' do
      cli.invoke(:auto, ['https://example.com'], { strategy: 'browserless' })

      expect(Html2rss).to have_received(:auto_source)
        .with('https://example.com', strategy: :browserless, items_selector: nil, max_redirects: nil,
                                     max_requests: nil)
    end

    it 'passes the rss format option to Html2rss.auto_source' do
      cli.invoke(:auto, ['https://example.com'], { format: 'rss' })

      expect(Html2rss).to have_received(:auto_source)
        .with('https://example.com', strategy: :faraday, items_selector: nil, max_redirects: nil,
                                     max_requests: nil)
    end

    it 'passes the jsonfeed format option to Html2rss.auto_json_feed' do
      cli.invoke(:auto, ['https://example.com'], { format: 'jsonfeed' })

      expect(Html2rss).to have_received(:auto_json_feed)
        .with('https://example.com', strategy: :faraday, items_selector: nil, max_redirects: nil,
                                     max_requests: nil)
    end

    it 'prints the jsonfeed output when requested' do
      expected_output = "#{JSON.pretty_generate(auto_json_feed)}\n"

      expect { cli.invoke(:auto, ['https://example.com'], { format: 'jsonfeed' }) }
        .to output(expected_output).to_stdout
    end

    it 'passes the items_selector option to Html2rss.auto_source' do
      cli.invoke(:auto, ['https://example.com'], { items_selector: '.item' })

      expect(Html2rss).to have_received(:auto_source)
        .with('https://example.com', strategy: :faraday, items_selector: '.item', max_redirects: nil,
                                     max_requests: nil)
    end

    it 'passes the max_redirects option to Html2rss.auto_source' do
      cli.invoke(:auto, ['https://example.com'], { max_redirects: 8 })

      expect(Html2rss).to have_received(:auto_source)
        .with('https://example.com', strategy: :faraday, items_selector: nil, max_redirects: 8, max_requests: nil)
    end

    it 'passes the max_requests option to Html2rss.auto_source' do
      cli.invoke(:auto, ['https://example.com'], { max_requests: 8 })

      expect(Html2rss).to have_received(:auto_source)
        .with('https://example.com', strategy: :faraday, items_selector: nil, max_redirects: nil, max_requests: 8)
    end

    context 'when the redirect limit is hit' do
      before do
        allow(Html2rss).to receive(:auto_source).and_raise(
          Faraday::FollowRedirects::RedirectLimitReached,
          'too many redirects; last one to: https://www.example.com/'
        )
      end

      it 'raises a CLI error with an actionable redirect hint' do
        expect { cli.auto('https://example.com') }
          .to raise_error(
            Thor::Error,
            /retry with --max-redirects 4 or use the final URL directly/
          )
      end
    end

    context 'when browserless connectivity fails' do
      before do
        allow(Html2rss).to receive(:auto_source).and_raise(
          Html2rss::RequestService::BrowserlessConnectionFailed,
          'Browserless connection failed (SocketError: getaddrinfo: Name or service not known).'
        )
      end

      it 'raises a CLI error with browserless diagnostics' do
        expect { cli.invoke(:auto, ['https://example.com'], { strategy: 'browserless' }) }
          .to raise_error(Thor::Error, /Browserless connection failed/)
      end
    end

    context 'when an anti-bot interstitial is detected' do
      before do
        allow(Html2rss).to receive(:auto_source).and_raise(
          Html2rss::RequestService::BlockedSurfaceDetected,
          'Blocked surface detected: Cloudflare anti-bot interstitial page. Retry with --strategy browserless.'
        )
      end

      it 'raises a CLI error with blocked-surface guidance' do
        expect { cli.auto('https://example.com') }
          .to raise_error(Thor::Error, /Blocked surface detected: Cloudflare anti-bot interstitial page/)
      end
    end
  end

  describe '#schema' do
    let(:schema_hash) { { 'type' => 'object', 'title' => 'html2rss' } }

    before do
      allow(Html2rss::Config).to receive(:json_schema).and_return(schema_hash)
      allow(Html2rss::Config).to receive(:json_schema_json).and_call_original
    end

    it 'prints the schema JSON to stdout' do
      expect { cli.schema }.to output("#{JSON.pretty_generate(schema_hash)}\n").to_stdout
    end

    it 'supports compact output' do
      expect { cli.invoke(:schema, [], { pretty: false }) }
        .to output("#{JSON.generate(schema_hash)}\n").to_stdout
    end

    it 'writes the schema to the requested file path', :aggregate_failures do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'nested', 'schema.json')

        expect { cli.invoke(:schema, [], { write: path }) }.to output("#{path}\n").to_stdout
        expect(JSON.parse(File.read(path))).to eq(schema_hash)
      end
    end
  end

  describe '#validate' do
    let(:result) { instance_double(Dry::Validation::Result, success?: success, errors:) }
    let(:errors) { instance_double(Dry::Validation::MessageSet, to_h: { selectors: ['bad config'] }) }

    before do
      allow(Html2rss::Config).to receive(:validate_yaml).and_return(result)
    end

    context 'when the config is valid' do
      let(:success) { true }

      it 'prints a success message' do
        expect { cli.validate('config.yml') }.to output("Configuration is valid\n").to_stdout
      end

      it 'passes the params option to runtime validation' do
        cli.invoke(:validate, ['config.yml'], { params: { 'query' => 'ruby' } })

        expect(Html2rss::Config).to have_received(:validate_yaml).with('config.yml', nil, params: { 'query' => 'ruby' })
      end
    end

    context 'when the config is invalid' do
      let(:success) { false }

      it 'raises a CLI error with runtime validation details' do
        expect { cli.validate('config.yml') }
          .to raise_error(Thor::Error, "Invalid configuration: #{errors.to_h}")
      end
    end
  end

  describe 'request budget failures' do
    before do
      allow(Html2rss).to receive(:feed).and_raise(
        Html2rss::RequestService::RequestBudgetExceeded,
        'Request budget exhausted'
      )
      allow(Html2rss).to receive(:config_from_yaml_file).and_return({ url: 'https://example.com' })
    end

    it 'raises a CLI error with an increased retry hint' do
      expect { cli.feed('example.yml') }
        .to raise_error(
          Thor::Error,
          /retry with --max-requests 2 or increase request.max_requests in the config/
        )
    end
  end
end
