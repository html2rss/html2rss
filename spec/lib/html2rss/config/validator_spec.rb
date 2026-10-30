# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Config::Validator do
  subject(:result) { described_class.new.call(config) }

  let(:base) do
    {
      channel: { url: 'https://example.com' },
      selectors: { items: { selector: '.article' } }
    }
  end

  describe 'selectors path bubbling' do
    let(:config) do
      base.merge(
        selectors: {
          items: { selector: '.article', pagination: { strategy: 'invalid_strategy' } }
        }
      )
    end

    it 'prefixes nested selector paths under :selectors', :aggregate_failures do
      expect(result).to be_failure
      expect(result.errors.map(&:path)).to include(%i[selectors items pagination])
    end
  end

  describe 'selector extractor path bubbling' do
    let(:config) do
      base.merge(
        selectors: {
          items: { selector: '.article' },
          title: { selector: 'h1', extractor: 'nope' }
        }
      )
    end

    it 'keeps the dynamic selector key and leaf', :aggregate_failures do
      expect(result).to be_failure
      expect(result.errors.map(&:path)).to include(%i[selectors title extractor])
    end
  end

  describe 'user-YAML edge rules' do
    {
      'relative channel url' => [{ channel: { url: '/relative' } }, [[%i[channel url], 'URL must be absolute']]],
      'channel url with unsupported scheme' => [
        { channel: { url: 'ftp://example.com' } },
        [[%i[channel url], "URL scheme 'ftp' is not supported"]]
      ],
      'channel url with @ in query' => [
        { channel: { url: 'https://example.com/?q=@x' } },
        [[%i[channel url], 'URL must not contain an @ character']]
      ],
      'channel url with @ in fragment' => [
        { channel: { url: 'https://example.com/#@x' } },
        [[%i[channel url], 'URL must not contain an @ character']]
      ],
      'channel url with @ in path' => [{ channel: { url: 'https://example.com/@x' } }, []],
      'blank channel url' => [{ channel: { url: '' } }, [[%i[channel url], 'must be filled']]],
      'relative channel image' => [
        { channel: { url: 'https://example.com', image: '/img.png' } },
        [[%i[channel image], 'URL must be absolute']]
      ],
      'malformed channel image' => [
        { channel: { url: 'https://example.com', image: 'not a uri' } },
        [[%i[channel image], 'URL must be absolute']]
      ],
      'absolute channel image' => [{ channel: { url: 'https://example.com', image: 'https://example.com/i.png' } }, []],
      'non-positive channel ttl' => [
        { channel: { url: 'https://example.com', ttl: 0 } },
        [[%i[channel ttl], 'must be greater than 0']]
      ],
      'non-positive auto_source limit' => [
        { auto_source: { limit: 0 } },
        [[%i[auto_source limit], 'must be greater than 0']]
      ],
      'non-positive request max_requests' => [
        { request: { max_requests: 0 } },
        [[%i[request max_requests], 'must be greater than 0']]
      ],
      'non-positive request total_timeout_seconds' => [
        { request: { total_timeout_seconds: 0 } },
        [[%i[request total_timeout_seconds], 'must be greater than 0']]
      ],
      'negative request max_redirects' => [
        { request: { max_redirects: -1 } },
        [[%i[request max_redirects], 'must be greater than or equal to 0']]
      ],
      'zero request max_redirects' => [{ request: { max_redirects: 0 } }, []],
      'positive request max_requests' => [{ request: { max_requests: 1 } }, []],
      'botasaurus max_retries above limit' => [
        { request: { botasaurus: { max_retries: 99 } } },
        [[%i[request botasaurus max_retries], 'must be less than or equal to 3']]
      ],
      'botasaurus unknown option' => [
        { request: { botasaurus: { bogus: 1 } } },
        [[%i[request botasaurus bogus], 'is not allowed']]
      ],
      'non-string header value' => [{ headers: { 'X' => 1 } },
                                    [[[:headers, 'X'], 'must be a String, but got Integer']]],
      'invalid stylesheet type' => [
        { stylesheets: [{ href: 'a', type: 'text/x' }] },
        [[[:stylesheets, 0, :type], 'must be one of: text/css, text/xsl']]
      ],
      'invalid gsub pattern inside selectors' => [
        { selectors: { title: { post_process: [{ name: 'gsub', pattern: '[', replacement: 'x' }] } } },
        [[%i[selectors title pattern], 'Premature end of pattern at [']]
      ]
    }.each do |label, (overrides, expected)|
      it "reports #{label}" do
        expect(described_class.new.call(base.merge(overrides)).errors.map { [_1.path, _1.text] }).to eq(expected)
      end
    end

    it 'surfaces dynamic_params_error as its own message' do
      expect(described_class.new.call(base.merge(dynamic_params_error: 'boom')).errors.map(&:text)).to eq(['boom'])
    end

    it 'requires selectors or auto_source' do
      expect(described_class.new.call(channel: { url: 'https://example.com' }).errors.map(&:text))
        .to eq(["Configuration must include at least 'selectors' or 'auto_source'"])
    end
  end
end
