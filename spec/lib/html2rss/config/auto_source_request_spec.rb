# frozen_string_literal: true

RSpec.describe Html2rss::Config::AutoSourceRequest do
  describe '#to_config' do
    let(:config) do
      described_class.new(
        url: 'https://example.com/blog',
        items_selector: '.post',
        request_controls: Html2rss::Config::RequestControls.new(
          strategy: :botasaurus,
          max_redirects: 8,
          max_requests: 5,
          explicit_keys: %i[strategy max_redirects max_requests]
        )
      ).to_config
    end

    it 'builds a top-level auto-source feed config', :aggregate_failures do
      expect(config[:strategy]).to eq(:botasaurus)
      expect(config[:request]).to eq(max_redirects: 8, max_requests: 5)
      expect(config.dig(:channel, :url)).to eq('https://example.com/blog')
      expect(config[:auto_source]).to eq(Html2rss::AutoSource::DEFAULT_CONFIG)
      expect(config[:selectors]).to eq(items: { selector: '.post', enhance: true })
    end

    it 'leaves optional request overrides unset so runtime config can apply defaults', :aggregate_failures do
      config = described_class.new(url: 'https://example.com/blog').to_config

      expect(config).not_to have_key(:request)
      expect(config[:selectors]).to be_nil
    end

    it 'adds local_file_path to the request', :aggregate_failures do
      controls = Html2rss::Config::RequestControls.new(max_redirects: 2, explicit_keys: %i[max_redirects])
      with_controls = described_class.new(url: 'https://example.com', local_file_path: '/p', request_controls: controls)

      expect(described_class.new(url: 'https://example.com', local_file_path: '/p').to_config[:request])
        .to eq(local_file_path: '/p')
      expect(with_controls.to_config[:request]).to eq(max_redirects: 2, local_file_path: '/p')
    end

    it 'keeps the selector hint off the config when none is given' do
      expect(described_class.new(url: 'https://example.com').to_config).not_to have_key(:selectors)
    end

    it 'rejects a malformed limit', :aggregate_failures do
      [0, -1, '5', 2.5].each do |limit|
        expect { described_class.new(url: 'https://example.com', limit:).to_config }
          .to raise_error(Html2rss::InvalidOption, /\Alimit must be/)
      end
    end

    it 'keeps a valid limit' do
      expect(described_class.new(url: 'https://example.com', limit: 3).to_config[:auto_source][:limit]).to eq(3)
    end

    it 'accepts the minimum limit of 1 and names the option when rejecting', :aggregate_failures do
      expect(described_class.new(url: 'https://example.com', limit: 1).to_config[:auto_source][:limit]).to eq(1)
      expect { described_class.new(url: 'https://example.com', limit: 0).to_config }
        .to raise_error(Html2rss::InvalidOption, /\Alimit must be/)
    end

    it 'puts only the default time zone and the url on the channel' do
      expect(described_class.new(url: 'https://example.com/x').to_config[:channel])
        .to eq(time_zone: 'UTC', url: 'https://example.com/x')
    end

    it 'leaves the auto-source defaults untouched when no overrides are given', :aggregate_failures do
      config = described_class.new(url: 'https://example.com').to_config

      expect(config[:auto_source]).to equal(Html2rss::AutoSource::DEFAULT_CONFIG)
      expect(config[:auto_source][:limit]).to eq(Html2rss::AutoSource::DEFAULT_LIMIT)
    end

    [true, false].each do |value|
      it "overrides cleanup.keep_different_domain with #{value} without mutating the defaults",
         :aggregate_failures do
        config = described_class.new(url: 'https://example.com', keep_different_domain: value).to_config

        defaults = Html2rss::AutoSource::DEFAULT_CONFIG
        expect(config[:auto_source][:cleanup]).to eq(defaults[:cleanup].merge(keep_different_domain: value))
        expect(config[:auto_source].except(:cleanup)).to eq(defaults.except(:cleanup))
      end
    end

    it 'overrides cleanup.keep_sponsored alone, keeping the other cleanup default', :aggregate_failures do
      config = described_class.new(url: 'https://example.com', keep_sponsored: true).to_config

      expect(config[:auto_source][:cleanup]).to eq(keep_different_domain: false, keep_sponsored: true)
      expect(Html2rss::AutoSource::DEFAULT_CONFIG[:cleanup].values).to all(be(false))
    end
  end

  describe '.from_shortcut' do
    it 'builds request controls from the shortcut keywords', :aggregate_failures do
      config = described_class.from_shortcut('https://example.com', strategy: :default, max_requests: 4).to_config

      expect(config[:strategy]).to eq(:default)
      expect(config[:request]).to eq(max_requests: 4)
      expect(config.dig(:channel, :url)).to eq('https://example.com')
    end

    it 'adds local_file_path to the request without dropping request limits' do
      config = described_class.from_shortcut('https://example.com', strategy: :local_file, max_redirects: 2,
                                                                    local_file_path: '/tmp/p.html').to_config

      expect(config[:request]).to eq(max_redirects: 2, local_file_path: '/tmp/p.html')
    end

    it 'rejects a url keyword beside the positional url' do
      expect { described_class.from_shortcut('https://a.test', strategy: :auto, url: 'https://b.test') }
        .to raise_error(Html2rss::InvalidOption, 'unknown keyword: :url')
    end

    it 'rejects an unknown member' do
      expect { described_class.from_shortcut('https://example.com', strategy: :auto, bogus: 1) }
        .to raise_error(ArgumentError, /bogus/)
    end
  end
end
