# frozen_string_literal: true

RSpec.describe Html2rss::CLI, '#scrape' do
  let(:feed_res) do
    instance_double(
      Html2rss::FeedResult, to_rss: '<rss/>', to_json_feed: { title: 'T' },
                            status: instance_double(Html2rss::Status, to_h: { ok: true })
    )
  end
  let(:run_scrape) { ->(args, options = {}) { described_class.new.invoke(:scrape, args, options) } }

  before { allow(Html2rss).to receive(:scrape).and_return(feed_res) }

  it 'forwards the documented defaults and prints the rss', :aggregate_failures do
    expect { run_scrape.call(['https://a.test']) }.to output("<rss/>\n").to_stdout
    expect(Html2rss).to have_received(:scrape).with(
      'https://a.test', strategy: :auto, items_selector: nil, max_redirects: nil, max_requests: nil,
                        local_file_path: nil, limit: nil, keep_different_domain: false
    )
  end

  it 'forwards every option', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
    expect do
      run_scrape.call(
        ['https://a.test'],
        { strategy: 'default', items_selector: '.x', max_redirects: 2, max_requests: 3, limit: 4,
          keep_different_domain: true }
      )
    end.to output.to_stdout
    expect(Html2rss).to have_received(:scrape).with(
      'https://a.test', strategy: :default, items_selector: '.x', max_redirects: 2, max_requests: 3,
                        local_file_path: nil, limit: 4, keep_different_domain: true
    )
  end

  it 'prints jsonfeed output and explain diagnostics', :aggregate_failures do
    expect do
      expect { run_scrape.call(['https://a.test'], { format: 'jsonfeed', explain: true }) }
        .to output("{\n  \"title\": \"T\"\n}\n").to_stdout
    end.to output("{\n  \"ok\": true\n}\n").to_stderr
  end

  it 'requires a url' do
    expect { run_scrape.call([nil]) }.to raise_error(Thor::Error, 'A URL is required unless --input is specified')
  end

  it 'scrapes a local file with the local_file strategy', :aggregate_failures do
    expect { run_scrape.call(['https://a.test'], { input: 'spec/fixtures/page_1.html' }) }.to output.to_stdout
    expect(Html2rss).to have_received(:scrape).with(
      'https://a.test', hash_including(strategy: :local_file,
                                       local_file_path: File.expand_path('spec/fixtures/page_1.html'))
    )
  end

  describe 'request failures' do
    {
      Html2rss::RequestService::RedirectLimitReached => 'too many. already retried the last redirect hop once; ' \
                                                        'retry with higher --max-redirects ' \
                                                        'or use the final URL directly.',
      Html2rss::RequestService::RequestBudgetExceeded => 'too many. retry with higher --max-requests or increase ' \
                                                         'request.max_requests in config.'
    }.each do |error_class, message|
      it "turns #{error_class.name.split('::').last} into a Thor::Error with advice" do
        allow(Html2rss).to receive(:scrape).and_raise(error_class, 'too many')

        expect { run_scrape.call(['https://a.test']) }.to raise_error(Thor::Error, message)
      end
    end

    [
      Html2rss::RequestService::BotasaurusConfigurationError,
      Html2rss::RequestService::BotasaurusConnectionFailed,
      Html2rss::RequestService::BotasaurusServiceError,
      Html2rss::RequestService::BlockedSurfaceDetected,
      Html2rss::InvalidOption,
      Html2rss::Url::InvalidUrlError
    ].each do |error_class|
      it "passes the #{error_class.name.split('::').last} message through" do
        allow(Html2rss).to receive(:scrape).and_raise(error_class, 'plain message')

        expect { run_scrape.call(['https://a.test']) }.to raise_error(Thor::Error, 'plain message')
      end
    end

    it 'does not swallow unrelated errors' do
      allow(Html2rss).to receive(:scrape).and_raise(ArgumentError, 'bug')

      expect { run_scrape.call(['https://a.test']) }.to raise_error(ArgumentError, 'bug')
    end
  end
end
