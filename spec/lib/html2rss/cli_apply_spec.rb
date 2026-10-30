# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Html2rss::CLI, '#apply' do
  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers -- CLI option wiring contracts
  subject(:cli) { described_class.new }

  let(:feed_res) do
    instance_double(
      Html2rss::FeedResult, to_rss: '<rss/>', to_json_feed: { title: 'T' },
                            status: instance_double(Html2rss::Status, to_h: { ok: true })
    )
  end
  let(:yaml_config) { { channel: { url: 'https://a.test' } } }
  let(:applied) { [] }
  let(:run_apply) do
    lambda do |args, options = {}|
      described_class.new.invoke(:apply, args, options)
      applied.last
    end
  end

  before do
    allow(Html2rss::Config).to receive(:from_yaml).and_return(yaml_config)
    allow(Html2rss).to receive(:apply) do |config|
      applied << config
      feed_res
    end
  end

  it 'passes an empty params hash by default and the given params otherwise', :aggregate_failures do
    expect(run_apply.call(['x.yml'])).to include(params: {})
    expect(run_apply.call(['x.yml'], { params: { 'q' => 'v' } })).to include(params: { 'q' => 'v' })
  end

  it 'reads an existing file through the file loader with the feed name' do
    allow(Html2rss).to receive(:config_from_yaml_file).and_return(yaml_config)

    Dir.mktmpdir do |dir|
      path = File.join(dir, 'feed.yml')
      File.write(path, 'x')
      run_apply.call([path, 'named'])

      expect(Html2rss).to have_received(:config_from_yaml_file).with(path, 'named')
    end
  end

  it 'parses non-file input as raw yaml content', :aggregate_failures do
    run_apply.call(['channel: {url: https://a.test}'])

    expect(Html2rss::Config).to have_received(:from_yaml).with('channel: {url: https://a.test}')
  end

  it 'applies request overrides from the options', :aggregate_failures do
    config = run_apply.call(['x.yml'], { strategy: 'default', max_redirects: 3, max_requests: 2 })

    expect(config).to include(strategy: :default)
    expect(config[:request]).to eq(max_redirects: 3, max_requests: 2)
  end

  context 'with blank request values in the config' do
    let(:yaml_config) do
      { strategy: nil, request: { max_redirects: nil, max_requests: nil, total_timeout_seconds: 9 },
        channel: { url: 'https://a.test' } }
    end

    it 'drops nil strategy and nil request limits but keeps the rest', :aggregate_failures do
      config = run_apply.call(['x.yml'])

      expect(config).not_to have_key(:strategy)
      expect(config[:request]).to eq(total_timeout_seconds: 9)
    end
  end

  context 'with only blank request values' do
    let(:yaml_config) { { request: { max_redirects: nil, max_requests: 4 }, channel: { url: 'https://a.test' } } }

    it 'keeps a populated request hash and only removes the blank keys', :aggregate_failures do
      config = run_apply.call(['x.yml'])

      expect(config[:request]).to eq(max_requests: 4)
    end
  end

  context 'with an entirely blank request' do
    let(:yaml_config) { { request: { max_redirects: nil }, channel: { url: 'https://a.test' } } }

    it 'removes the empty request hash' do
      expect(run_apply.call(['x.yml'])).not_to have_key(:request)
    end
  end

  context 'with a non-hash request' do
    let(:yaml_config) { { request: 'oops', channel: { url: 'https://a.test' } } }

    it 'leaves it for validation to reject' do
      expect(run_apply.call(['x.yml'])).to include(request: 'oops')
    end
  end

  describe '--input' do
    let(:html) { '<html><head><link rel="canonical" href="https://canon.test/page"></head></html>' }

    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, 'page.html').tap { |file| File.write(file, html) } }

    after { FileUtils.remove_entry(dir) }

    it 'switches to the local_file strategy with an expanded path', :aggregate_failures do
      config = run_apply.call(['x.yml'], { input: path })

      expect(config).to include(strategy: :local_file)
      expect(config[:request]).to eq(local_file_path: File.expand_path(path))
    end

    it 'keeps other request settings and an existing channel url', :aggregate_failures do
      yaml_config[:request] = { max_requests: 5 }
      config = run_apply.call(['x.yml'], { input: path })

      expect(config[:request]).to eq(max_requests: 5, local_file_path: File.expand_path(path))
      expect(config[:channel]).to eq(url: 'https://a.test')
    end

    context 'without a channel url' do
      let(:yaml_config) { { channel: { title: 'T' } } }

      it 'detects the base url from the html and keeps channel fields', :aggregate_failures do
        config = run_apply.call(['x.yml'], { input: path })

        expect(config[:channel]).to eq(title: 'T', url: 'https://canon.test/page')
      end
    end

    context 'without a channel section' do
      let(:yaml_config) { {} }

      it 'creates the channel from the detected url' do
        expect(run_apply.call(['x.yml'], { input: path })[:channel]).to eq(url: 'https://canon.test/page')
      end
    end

    context 'when no base url can be detected' do
      let(:html) { '<html></html>' }
      let(:yaml_config) { {} }

      it 'raises with the channel.url hint' do
        expect { run_apply.call(['x.yml'], { input: path }) }.to raise_error(
          Thor::Error,
          'Could not auto-detect a base URL from HTML metadata. Please specify a channel.url in the config.'
        )
      end
    end

    it 'raises when the input file does not exist' do
      expect { run_apply.call(['x.yml'], { input: '/nonexistent/page.html' }) }
        .to raise_error(Thor::Error, 'Input file does not exist: /nonexistent/page.html')
    end
  end

  it 'prints the status JSON to stderr with --explain' do
    expect do
      run_apply.call(['x.yml'], { explain: true })
    end.to output("{\n  \"ok\": true\n}\n").to_stderr.and output.to_stdout
  end

  it 'prints jsonfeed output for --format jsonfeed' do
    expect { run_apply.call(['x.yml'], { format: 'jsonfeed' }) }.to output("{\n  \"title\": \"T\"\n}\n").to_stdout
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
end
