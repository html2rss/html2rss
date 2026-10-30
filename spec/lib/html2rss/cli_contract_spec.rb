# frozen_string_literal: true

RSpec.describe Html2rss::CLI do
  describe 'command contract' do
    let(:strategies) { Html2rss::CLI::STRATEGY_OPTION_ENUM }
    let(:strategy_desc) { Html2rss::CLI::STRATEGY_OPTION_DESC }
    let(:contract) do
      {
        'inspect' => {
          usage: 'inspect [TARGET]',
          description: 'Fetch diagnostics for a URL (final URL, status, alternates, surface)',
          options: {
            strategy: { type: :string, default: nil, enum: strategies, aliases: [], description: strategy_desc },
            file: { type: :string, default: nil, enum: nil, aliases: [],
                    description: 'Candidate list file (one URL or slug\\turl per line)' },
            format: { type: :string, default: 'text', enum: %w[text json], aliases: [], description: nil },
            deep: { type: :boolean, default: false, enum: nil, aliases: [],
                    description: 'Single Botasaurus diagnostic hop when BOTASAURUS_SCRAPER_URL is set' }
          }
        },
        'recon' => {
          usage: 'recon [TARGET]',
          description: 'Probe a URL or candidate list for redirect chains, native feeds, and surface readiness',
          options: {
            strategy: { type: :string, default: nil, enum: strategies, aliases: [], description: strategy_desc },
            file: { type: :string, default: nil, enum: nil, aliases: [],
                    description: 'Candidate list file (one URL or slug\\turl per line)' },
            cache_dir: { type: :string, default: nil, enum: nil, aliases: [],
                         description: 'Directory to cache raw HTML snapshots' },
            verdict: { type: :string, default: nil, enum: nil, aliases: [],
                       description: 'Filter batch output by verdict (BUILD, DEFER, DROP)' },
            url_only: { type: :boolean, default: false, enum: nil, aliases: [],
                        description: 'Emit only URLs matching verdict (for pipe chaining)' },
            format: { type: :string, default: 'text', enum: %w[text json tsv], aliases: [], description: nil }
          }
        },
        'capture' => {
          usage: 'capture [TARGET]', description: 'Analyze a URL or HTML and output a curated YAML feed config',
          options: {
            strategy: { type: :string, default: nil, enum: strategies, aliases: [], description: strategy_desc },
            max_redirects: { type: :numeric, default: nil, enum: nil, aliases: [],
                             description: 'Max redirects to follow' },
            max_requests: { type: :numeric, default: nil, enum: nil, aliases: [], description: 'Max request budget' },
            input: { type: :string, default: nil, enum: nil, aliases: [], description: 'Local HTML file path' },
            items_selector: { type: :string, default: nil, enum: nil, aliases: [],
                              description: 'CSS selector hint for items' },
            output_dir: { type: :string, default: nil, enum: nil, aliases: ['-o'],
                          description: 'Base directory to write <domain>/index.yml' },
            write: { type: :string, default: nil, enum: nil, aliases: ['-w'],
                     description: 'Specific file path to write YAML to' },
            topics: { type: :string, default: nil, enum: nil, aliases: ['-t'],
                      description: 'Comma-separated directory topics' },
            title: { type: :string, default: nil, enum: nil, aliases: [],
                     description: 'Directory and channel title override' },
            summary: { type: :string, default: nil, enum: nil, aliases: [], description: 'Directory summary override' },
            enhance: { type: :boolean, default: nil, enum: nil, aliases: [],
                       description: 'Force enhance: true on items selector' },
            force: { type: :boolean, default: false, enum: nil, aliases: [], description: 'Bypass native feed check' },
            limit: { type: :numeric, default: nil, enum: nil, aliases: [], description: 'Article limit (default: 25)' },
            explain: { type: :boolean, default: false, enum: nil, aliases: [],
                       description: 'Print capture diagnostics to stderr' }
          }
        },
        'test' => {
          usage: 'test [CONFIG_INPUT] [feed_name]',
          description: 'Validate schema AND execute live extraction (fails on 0 items)',
          options: {
            params: { type: :hash, default: {}, enum: nil, aliases: [], description: nil },
            min_items: { type: :numeric, default: 1, enum: nil, aliases: [],
                         description: 'Minimum required articles to pass' },
            strict_quality: { type: :boolean, default: false, enum: nil, aliases: [],
                              description: 'Fail when ship-quality audit thresholds are exceeded' },
            compare_enhance: { type: :boolean, default: false, enum: nil, aliases: [],
                               description: 'Compare extraction with enhance on vs off (diagnostic only)' },
            strategy: { type: :string, default: nil, enum: strategies, aliases: [], description: strategy_desc },
            json: { type: :boolean, default: false, enum: nil, aliases: [],
                    description: 'Output test outcome as JSON' },
            xml: { type: :boolean, default: false, enum: nil, aliases: [],
                   description: 'Dump RSS XML alongside summary' },
            quiet: { type: :boolean, default: false, enum: nil, aliases: ['-q'], description: nil }
          }
        },
        'apply' => {
          usage: 'apply [CONFIG_INPUT] [feed_name]', description: 'Print RSS built from YAML config to stdout',
          options: {
            strategy: { type: :string, default: nil, enum: strategies, aliases: [], description: strategy_desc },
            max_redirects: { type: :numeric, default: nil, enum: nil, aliases: [],
                             description: 'Max redirects to follow' },
            max_requests: { type: :numeric, default: nil, enum: nil, aliases: [], description: 'Max request budget' },
            input: { type: :string, default: nil, enum: nil, aliases: [], description: 'Local HTML file path' },
            format: { type: :string, default: 'rss', enum: %w[rss jsonfeed], aliases: [], description: nil },
            explain: { type: :boolean, default: false, enum: nil, aliases: [],
                       description: 'Print status JSON to stderr' },
            params: { type: :hash, default: {}, enum: nil, aliases: [], description: nil }
          }
        },
        'scrape' => {
          usage: 'scrape [URL]', description: 'Automatically source an RSS feed from a URL (one-shot auto-source)',
          options: {
            strategy: { type: :string, default: nil, enum: strategies, aliases: [], description: strategy_desc },
            max_redirects: { type: :numeric, default: nil, enum: nil, aliases: [],
                             description: 'Max redirects to follow' },
            max_requests: { type: :numeric, default: nil, enum: nil, aliases: [], description: 'Max request budget' },
            input: { type: :string, default: nil, enum: nil, aliases: [], description: 'Local HTML file path' },
            format: { type: :string, default: 'rss', enum: %w[rss jsonfeed], aliases: [], description: nil },
            explain: { type: :boolean, default: false, enum: nil, aliases: [],
                       description: 'Print status JSON to stderr' },
            items_selector: { type: :string, default: nil, enum: nil, aliases: [],
                              description: 'CSS selector hint for items' },
            limit: { type: :numeric, default: nil, enum: nil, aliases: [], description: 'Max articles (auto-source)' },
            keep_different_domain: { type: :boolean, default: false, enum: nil, aliases: [],
                                     description: 'Allow published items to link to any domain ' \
                                                  'supplied by the source (no affiliation/safety check)' }
          }
        },
        'validate' => {
          usage: 'validate [CONFIG_FILES...]', description: 'Validate one or more YAML configs against the JSON Schema',
          options: {
            params: { type: :hash, default: {}, enum: nil, aliases: [], description: nil },
            quiet: { type: :boolean, default: false, enum: nil, aliases: ['-q'], description: nil }
          }
        },
        'schema' => {
          usage: 'schema', description: 'Print or export the configuration JSON Schema',
          options: {
            pretty: { type: :boolean, default: true, enum: nil, aliases: [], description: 'Pretty-print JSON' },
            write: { type: :string, default: nil, enum: nil, aliases: ['-w'],
                     description: 'Write schema to file path' }
          }
        },
        'mcp' => {
          usage: 'mcp', description: 'Start the MCP server for AI agent and IDE consumption',
          options: {
            transport: { type: :string, default: 'stdio', enum: %w[stdio http], aliases: [], description: nil },
            port: { type: :numeric, default: 8080, enum: nil, aliases: [], description: nil }
          }
        },
        'doctor' => {
          usage: 'doctor [TYPE]', description: 'Runtime preflight checks (botasaurus)',
          options: {
            sample: { type: :string, default: nil, enum: nil, aliases: [],
                      description: 'Optional URL for a Botasaurus sample scrape' }
          }
        }
      }
    end

    it 'defines exactly the documented commands' do
      expect(described_class.commands.keys).to eq(contract.keys)
    end

    it 'defines usage, description and options per command', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      contract.each do |name, expected|
        command = described_class.commands.fetch(name)
        actual = command.options.transform_values do |option|
          { type: option.type, default: option.default, enum: option.enum, aliases: option.aliases,
            description: option.description }
        end

        expect([name, command.usage, command.description, actual])
          .to eq([name, expected[:usage], expected[:description], expected[:options]])
      end
    end

    it 'maps the feed and auto aliases' do
      expect(described_class.map).to include('feed' => 'apply', 'auto' => 'scrape')
    end

    it 'exits non-zero on failure' do
      expect(described_class.exit_on_failure?).to be(true)
    end
  end
end
