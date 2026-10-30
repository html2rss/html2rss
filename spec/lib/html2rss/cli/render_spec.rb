# frozen_string_literal: true

RSpec.describe Html2rss::CLI::Render do
  # rubocop:disable RSpec/ExampleLength -- exact output contracts
  let(:view_attributes) do
    {
      requested: 'https://a.test/x', final: 'https://a.test/x', status: 200, surface: 'listing', articles_count: 4,
      verdict: nil, native_feed: nil, alternate_feeds: [], notes: [], strategy: nil
    }
  end
  let(:view) { Html2rss::CLI::ProbeView.new(**view_attributes) }
  let(:recon_result) do
    Html2rss::Recon::Result.new(
      requested_url: 'https://a.test/x', final_url: 'https://a.test/y', status: 200,
      verdict: Html2rss::Recon::Verdict[:build], native_feed: Html2rss::Url.from_absolute('https://a.test/feed'),
      surface_category: 'listing', articles_count: 3, scheme_downgrade: false, notes: %w[n1 n2], html_bytesize: 10
    )
  end

  describe '.probe_card' do
    it 'prints requested url, surface line and a blank line' do
      expect { described_class.probe_card(view) }.to output(
        "https://a.test/x\n        Surface:  listing (4 articles)\n\n"
      ).to_stdout
    end

    it 'prints the final url with its status when it differs' do
      moved = view.with(final: 'https://a.test/y', status: nil)

      expect { described_class.probe_card(moved) }.to output(
        "https://a.test/x\n        Final:    https://a.test/y (HTTP ERR)\n        Surface:  listing (4 articles)\n\n"
      ).to_stdout
    end

    it 'prints the final status code when present' do
      moved = view.with(final: 'https://a.test/y', status: 301)

      expect { described_class.probe_card(moved) }.to output(%r{Final:    https://a.test/y \(HTTP 301\)\n}).to_stdout
    end

    it 'does not print a final line without a final url' do
      expect { described_class.probe_card(view.with(final: nil)) }.not_to output(/Final:/).to_stdout
    end

    it 'prints feeds, native feed, notes and strategy' do
      full = view.with(
        alternate_feeds: [{ href: 'https://a.test/1.xml' }, { 'href' => 'https://a.test/2.xml' }, { type: 'x' }],
        native_feed: 'https://a.test/feed', notes: %w[n1 n2], strategy: :default
      )

      expect { described_class.probe_card(full) }.to output(
        "https://a.test/x\n        Surface:  listing (4 articles)\n        " \
        "Feeds:    https://a.test/1.xml, https://a.test/2.xml\n        " \
        "Feed:     https://a.test/feed\n        Notes:    n1, n2\n        Strategy: default\n\n"
      ).to_stdout
    end

    it 'omits the feeds line when no alternate has an href' do
      expect { described_class.probe_card(view.with(alternate_feeds: [{ type: 'x' }])) }
        .not_to output(/Feeds:/).to_stdout
    end

    {
      build: "\e[32m", defer: "\e[33m", drop: "\e[31m"
    }.each do |name, color|
      it "colors the #{name} verdict label" do
        labelled = view.with(verdict: Html2rss::Recon::Verdict[name])

        expect { described_class.probe_card(labelled) }.to output(
          a_string_starting_with("#{color}[#{name.to_s.upcase}]\e[0m https://a.test/x\n")
        ).to_stdout
      end
    end
  end

  describe '.recon_output' do
    it 'prints only urls with url_only' do
      expect { described_class.recon_output([recon_result], format: 'json', batch_mode: true, url_only: true) }
        .to output("https://a.test/x\n").to_stdout
    end

    it 'prints a header and tab separated rows for tsv' do
      expect { described_class.recon_output([recon_result], format: 'tsv', batch_mode: true) }.to output(
        "verdict\tstatus\trequested_url\tfinal_url\tnative_feed\tnotes\n" \
        "BUILD\t200\thttps://a.test/x\thttps://a.test/y\thttps://a.test/feed\tn1; n2\n"
      ).to_stdout
    end

    it 'prints dashes for missing tsv fields' do
      bare = recon_result.with(status: nil, native_feed: nil, notes: [])

      expect { described_class.recon_output([bare], format: 'tsv', batch_mode: true) }
        .to output(%r{BUILD\t-\thttps://a.test/x\thttps://a.test/y\t-\t\n\z}).to_stdout
    end

    it 'prints the first result for single json' do
      expect { described_class.recon_output([recon_result], format: 'json', batch_mode: false) }.to output(
        satisfy { |text| JSON.parse(text).values_at('requested_url', 'verdict') == ['https://a.test/x', 'build'] }
      ).to_stdout
    end

    it 'prints a list for batch json' do
      expect { described_class.recon_output([recon_result], format: 'json', batch_mode: true) }.to output(
        satisfy { |text| JSON.parse(text).map { _1['requested_url'] } == ['https://a.test/x'] }
      ).to_stdout
    end

    it 'renders text cards otherwise' do
      expect { described_class.recon_output([recon_result], format: 'text', batch_mode: false) }.to output(
        a_string_starting_with("\e[32m[BUILD]\e[0m https://a.test/x\n        Final:    https://a.test/y (HTTP 200)\n")
      ).to_stdout
    end
  end

  describe '.inspect_output' do
    let(:wire) { { requested_url: 'https://a.test/x', surface_category: 'listing', articles_count: 1 } }

    it 'prints json payloads' do
      expect { described_class.inspect_output([wire], format: 'json', batch_mode: false) }
        .to output("#{JSON.pretty_generate(wire)}\n").to_stdout
    end

    it 'prints text cards for any other format' do
      expect { described_class.inspect_output([wire], format: 'text', batch_mode: false) }
        .to output("https://a.test/x\n        Surface:  listing (1 articles)\n\n").to_stdout
    end
  end

  describe '.json' do
    it 'prints the first element unless batch' do
      expect { described_class.json([{ a: 1 }, { b: 2 }], false) }.to output("{\n  \"a\": 1\n}\n").to_stdout
    end

    it 'prints the whole list for batch' do
      expect { described_class.json([{ a: 1 }], true) }.to output("[\n  {\n    \"a\": 1\n  }\n]\n").to_stdout
    end
  end

  describe '.test_card' do
    let(:result) do
      Html2rss::Test::Result.new(
        success: true, item_count: 2, channel_title: 'Chan', channel_url: 'https://a.test', strategy_used: :default,
        duration_seconds: 1.5, validation_issues: nil, error_message: nil, failure_kind: nil, rss: '<rss/>',
        sample_items: [
          { title: 'One', url: 'https://a.test/1', published_at: DateTime.new(2024, 1, 2) },
          { title: 'Two', url: 'https://a.test/2', published_at: nil }
        ]
      )
    end

    it 'prints a success summary with samples' do
      expect { described_class.test_card(result, 'cfg.yml') }.to output(
        "\e[32m✓ Schema valid\e[0m (cfg.yml)\n" \
        "\e[32m✓ Extracted 2 items in 1.5s\e[0m (strategy: default)\n" \
        "\nChannel: Chan (https://a.test)\n" \
        "Sample items:\n  1. 2024-01-02T00:00:00+00:00 | One\n     https://a.test/1\n  2. Two\n     https://a.test/2\n"
      ).to_stdout
    end

    it 'omits the samples section without samples' do
      expect { described_class.test_card(result.with(sample_items: []), 'cfg.yml') }
        .not_to output(/Sample items/).to_stdout
    end

    it 'prints failures with error and schema issues on stderr' do
      issue = Html2rss::Config::ValidationIssue.new(path: [:channel], code: :missing_key, message: 'm',
                                                    expected: nil, actual: nil)
      failed = result.with(success: false, error_message: 'bad', validation_issues: [issue])

      expect { described_class.test_card(failed, 'cfg.yml') }.to output(
        "\e[31m✗ Test failed\e[0m (cfg.yml)\n  Error: bad\n  Schema error #{issue}\n"
      ).to_stderr
    end

    it 'omits the error line without an error message' do
      expect { described_class.test_card(result.with(success: false), 'x') }
        .to output("\e[31m✗ Test failed\e[0m (x)\n").to_stderr
    end
  end
  # rubocop:enable RSpec/ExampleLength
end
