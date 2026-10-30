# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Html2rss::CLI, '#recon' do
  # rubocop:disable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers -- CLI target/verdict contracts
  let(:verdict) { :build }
  let(:results) { [recon_result.call('https://a.test/x', verdict)] }
  let(:run_recon) { ->(args, options = {}) { described_class.new.invoke(:recon, args, options) } }
  let(:recon_result) do
    lambda do |url, kind|
      Html2rss::Recon::Result.new(
        requested_url: url, final_url: url, status: 200, verdict: Html2rss::Recon::Verdict[kind],
        native_feed: nil, surface_category: 'listing', articles_count: 1, scheme_downgrade: false, notes: [],
        html_bytesize: 1
      )
    end
  end

  before { allow(Html2rss::Recon).to receive(:batch).and_return(results) }

  it 'probes a single url with the default strategy and no cache', :aggregate_failures do
    expect { run_recon.call(['https://a.test/x'], { format: 'tsv' }) }
      .to output(%r{BUILD\t200\thttps://a.test/x}).to_stdout
    expect(Html2rss::Recon).to have_received(:batch).with(['https://a.test/x'], strategy: :auto, cache_dir: nil)
  end

  it 'forwards the strategy and cache directory', :aggregate_failures do
    expect { run_recon.call(['https://a.test/x'], { strategy: 'default', cache_dir: '/tmp/c', format: 'tsv' }) }
      .to output.to_stdout
    expect(Html2rss::Recon).to have_received(:batch).with(['https://a.test/x'], strategy: :default,
                                                                                cache_dir: '/tmp/c')
  end

  it 'requires a target' do
    expect { run_recon.call([]) }.to raise_error(Thor::Error, 'A target URL, --file, or stdin (-) is required')
  end

  describe 'candidate lists' do
    let(:dir) { Dir.mktmpdir }
    let(:path) do
      File.join(dir, 'urls.txt').tap do |file|
        File.write(file, "# comment\n\n  https://a.test/1  \nslug\t https://a.test/2 \n  \n#another\n")
      end
    end

    after { FileUtils.remove_entry(dir) }

    it 'reads urls from --file, skipping comments and blanks and taking the url after a tab', :aggregate_failures do
      expect { run_recon.call([nil], { file: path, format: 'tsv' }) }.to output.to_stdout
      expect(Html2rss::Recon).to have_received(:batch)
        .with(%w[https://a.test/1 https://a.test/2], strategy: :auto, cache_dir: nil)
    end

    it 'prefers --file over a target', :aggregate_failures do
      expect { run_recon.call(['https://ignored.test'], { file: path, format: 'tsv' }) }.to output.to_stdout
      expect(Html2rss::Recon).to have_received(:batch).with(%w[https://a.test/1 https://a.test/2], anything)
    end

    it 'reads stdin for a dash', :aggregate_failures do
      allow($stdin).to receive(:readlines).and_return(["https://s.test/1\n", "# skip\n", "x\thttps://s.test/2\n"])

      expect { described_class.new([], { format: 'tsv' }).recon('-') }.to output.to_stdout
      expect(Html2rss::Recon).to have_received(:batch).with(%w[https://s.test/1 https://s.test/2], anything)
    end

    it 'does not exit non-zero for batches' do
      allow(Html2rss::Recon).to receive(:batch).and_return([recon_result.call('https://a.test/1', :drop)])

      expect { run_recon.call([nil], { file: path, format: 'tsv' }) }.to output.to_stdout
    end
  end

  describe 'exit codes' do
    {
      defer: 3, drop: 1
    }.each do |kind, code|
      it "exits #{code} for a single #{kind} result", :aggregate_failures do
        allow(Html2rss::Recon).to receive(:batch).and_return([recon_result.call('https://a.test/x', kind)])
        exit_status = nil

        expect do
          run_recon.call(['https://a.test/x'], { format: 'tsv' })
        rescue SystemExit => error
          exit_status = error.status
        end.to output.to_stdout
        expect(exit_status).to eq(code)
      end
    end

    it 'returns normally for a single build result' do
      expect { run_recon.call(['https://a.test/x'], { format: 'tsv' }) }.to output.to_stdout
    end

    it 'does not exit for an empty result set' do
      allow(Html2rss::Recon).to receive(:batch).and_return([])

      expect { run_recon.call(['https://a.test/x'], { format: 'tsv' }) }.to output.to_stdout
    end
  end

  describe '--verdict' do
    let(:results) { [recon_result.call('https://a.test/x', :defer)] }

    it 'keeps matching results, ignoring case', :aggregate_failures do
      expect do
        expect { run_recon.call(['https://a.test/x'], { verdict: 'DeFer', format: 'tsv', url_only: true }) }
          .to raise_error(SystemExit)
      end.to output("https://a.test/x\n").to_stdout
    end

    it 'fails for a single target without a matching verdict' do
      expect { run_recon.call(['https://a.test/x'], { verdict: 'build' }) }
        .to raise_error(Thor::Error, 'No results matched verdict BUILD')
    end

    it 'rejects unknown verdicts' do
      expect { run_recon.call(['https://a.test/x'], { verdict: 'nope' }) }
        .to raise_error(Thor::Error, 'unknown verdict: "nope"')
    end

    it 'does not fail batches without matches', :aggregate_failures do
      allow($stdin).to receive(:readlines).and_return(["https://a.test/x\n"])

      expect { described_class.new([], { verdict: 'build', format: 'tsv' }).recon('-') }
        .to output("verdict\tstatus\trequested_url\tfinal_url\tnative_feed\tnotes\n").to_stdout
    end

    it 'does not fail when there were no results at all' do
      allow(Html2rss::Recon).to receive(:batch).and_return([])

      expect { run_recon.call(['https://a.test/x'], { verdict: 'build', format: 'tsv' }) }.to output.to_stdout
    end
  end
  # rubocop:enable RSpec/ExampleLength, RSpec/MultipleMemoizedHelpers
end
