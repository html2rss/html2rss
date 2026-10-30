# frozen_string_literal: true

RSpec.describe Html2rss::Test do
  let(:valid_config) do
    {
      channel: {
        title: 'Example',
        url: 'https://example.com/news',
        time_zone: 'UTC'
      },
      selectors: {
        items: { selector: 'article', enhance: false },
        title: { selector: 'h2' },
        url: { selector: 'a', extractor: 'href' }
      }
    }
  end

  let(:invalid_config) do
    {
      channel: {
        title: 'Missing URL'
      }
    }
  end

  let(:fake_rss_items) do
    [
      instance_double(
        RSS::Rss::Channel::Item,
        title: 'First Example Article Title',
        link: 'https://example.com/news/1',
        pubDate: nil
      ),
      instance_double(
        RSS::Rss::Channel::Item,
        title: 'Second Example Article Title',
        link: 'https://example.com/news/2',
        pubDate: nil
      )
    ]
  end

  let(:fake_rss) do
    instance_double(RSS::Rss, items: fake_rss_items)
  end

  let(:fake_feed_result) do
    status = instance_double(
      Html2rss::Status,
      selected_strategy: :default,
      entry_url: 'https://example.com/news',
      scrape_url: 'https://example.com/news'
    )
    instance_double(
      Html2rss::FeedResult,
      to_rss: fake_rss,
      channel_title: 'Example',
      status:
    )
  end

  describe '.call' do
    context 'when schema validation fails' do
      it 'returns a failed Test::Result with validation errors', :aggregate_failures do
        result = described_class.call(invalid_config)
        expect(result.success).to be(false)
        expect(result.valid_schema?).to be(false)
        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind[:schema])
        expect(result.response_body).to be_nil
      end
    end

    context 'when schema is valid and items are extracted' do
      before do
        outcome = Html2rss::FeedPipeline::PipelineOutcome.new(
          response: Html2rss::RequestService::Response.new(
            url: 'https://example.com/news',
            headers: { 'content-type' => 'text/html' },
            body: '<html></html>'
          ),
          articles: [],
          dedup_dropped: 0,
          selected_strategy: :default,
          attempt_count: 0,
          strategy_attempts: [],
          admission_drops: {},
          scrape_target: nil,
          entry_resolution: nil
        )
        pipeline = instance_double(Html2rss::FeedPipeline, to_outcome_and_result: [outcome, fake_feed_result])
        allow(Html2rss::FeedPipeline).to receive(:new).and_return(pipeline)
        allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_return(nil)
      end

      it 'returns a successful Test::Result with article count, samples, and rss', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        result = described_class.call(valid_config, min_items: 1)
        expect(result.success).to be(true)
        expect(result.item_count).to eq(2)
        expect(result.sample_items.size).to eq(2)
        expect(result.rss).to be_a(String)
        expect(result.failure_kind).to be_nil
      end

      it 'keeps the fetched page body in-process and off the public test hash', :aggregate_failures do
        result = described_class.call(valid_config, min_items: 1)

        expect(result.response_body).to eq('<html></html>')
        expect(result.to_h).not_to have_key(:response_body)
      end

      it 'attaches quality_report from feed audit', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        result = described_class.call(valid_config, min_items: 1)

        expect(result.quality_report).to be_a(Html2rss::Test::QualityReport)
        expect(result.quality_report.warnings).to be_empty
        expect(result.quality_report.metrics).to include(item_count: 2, unique_url_count: 2)
        expect(result.to_h[:quality_report]).to include(
          warnings: [],
          metrics: hash_including(item_count: 2)
        )
      end

      it 'warns on url_mismatch when scrape URL differs from channel.url', :aggregate_failures do
        allow(fake_feed_result.status).to receive(:scrape_url).and_return('https://example.com/blog/list')

        result = described_class.call(valid_config, min_items: 1)

        expect(result.quality_report.warnings).to include(:url_mismatch)
        expect(result.quality_report.metrics[:url_mismatch]).to be(true)
      end

      it 'advises when a native feed is discovered at channel.url', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        native = Html2rss::Url.from_absolute('https://example.com/feed.xml')
        allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_return(native)

        result = described_class.call(valid_config, min_items: 1)

        expect(result.quality_report.warnings).to include(:native_feed_present)
        expect(result.quality_report.native_feed).to eq('https://example.com/feed.xml')
        expect(result.quality_report.defer_reason).to eq(:native_feed)
        expect(result.success).to be(true)
      end

      it 'fails if extracted items are below min_items', :aggregate_failures do
        result = described_class.call(valid_config, min_items: 5)
        expect(result.success).to be(false)
        expect(result.error_message).to include('Extracted 2 items (minimum required: 5)')
        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind[:min_items])
        expect(result.rss).to be_nil
      end

      it 'keeps the fetched page body when the item count is below min_items' do
        result = described_class.call(valid_config, min_items: 5)

        expect(result.response_body).to eq('<html></html>')
      end

      it 'keeps warn-only quality_report when strict_quality is false despite duplicate URLs', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        duplicate_items = [
          instance_double(RSS::Rss::Channel::Item, title: 'Story One Title Here', link: 'https://example.com/same',
                                                   pubDate: nil),
          instance_double(RSS::Rss::Channel::Item, title: 'Story Two Title Here', link: 'https://example.com/same',
                                                   pubDate: nil)
        ]
        allow(fake_rss).to receive(:items).and_return(duplicate_items)

        result = described_class.call(valid_config, min_items: 1, strict_quality: false)

        expect(result.success).to be(true)
        expect(result.quality_report.warnings).to include(:duplicate_urls)
        expect(result.failure_kind).to be_nil
      end

      it 'fails with :quality when strict_quality and duplicate URLs', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        duplicate_items = [
          instance_double(RSS::Rss::Channel::Item, title: 'Story One Title Here', link: 'https://example.com/same',
                                                   pubDate: nil),
          instance_double(RSS::Rss::Channel::Item, title: 'Story Two Title Here', link: 'https://example.com/same',
                                                   pubDate: nil)
        ]
        allow(fake_rss).to receive(:items).and_return(duplicate_items)

        result = described_class.call(valid_config, min_items: 1, strict_quality: true)

        expect(result.success).to be(false)
        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind[:quality])
        expect(result.error_message).to include('duplicate_urls')
        expect(result.rss).to be_nil
        expect(result.quality_report.warnings).to include(:duplicate_urls)
      end

      it 'fails with :quality when strict_quality and more than half the titles are junk', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        junk_items = [
          instance_double(RSS::Rss::Channel::Item, title: 'Read More', link: 'https://example.com/a', pubDate: nil),
          instance_double(RSS::Rss::Channel::Item, title: 'Learn More', link: 'https://example.com/b', pubDate: nil),
          instance_double(RSS::Rss::Channel::Item, title: 'Valid Article Title Here', link: 'https://example.com/c',
                                                   pubDate: nil)
        ]
        allow(fake_rss).to receive(:items).and_return(junk_items)

        result = described_class.call(valid_config, min_items: 1, strict_quality: true)

        expect(result.success).to be(false)
        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind[:quality])
        expect(result.error_message).to include('generic_titles')
      end

      it 'prefers :min_items over :quality when both would fail', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        duplicate_items = [
          instance_double(RSS::Rss::Channel::Item, title: 'Story One Title Here', link: 'https://example.com/same',
                                                   pubDate: nil),
          instance_double(RSS::Rss::Channel::Item, title: 'Story Two Title Here', link: 'https://example.com/same',
                                                   pubDate: nil)
        ]
        allow(fake_rss).to receive(:items).and_return(duplicate_items)

        result = described_class.call(valid_config, min_items: 5, strict_quality: true)

        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind[:min_items])
      end

      it 'returns the exact failure result for a schema-invalid config', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        config = valid_config.merge(strategy: :default, channel: valid_config[:channel].merge(ttl: 'x'))
        result = described_class.call(config)

        expect(result).to have_attributes(
          success: false, item_count: 0, sample_items: [], channel_title: 'Example',
          channel_url: 'https://example.com/news', strategy_used: :default, duration_seconds: 0.0,
          error_message: 'Configuration schema validation failed',
          failure_kind: Html2rss::Test::FailureKind[:schema], rss: nil, quality_report: nil,
          enhance_compare: nil, response_body: nil
        )
        expect(result.validation_issues).not_to be_empty
      end

      it 'reports the exact result for a successful run', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(10.0, 11.23456)
        allow(fake_feed_result.status).to receive(:selected_strategy).and_return(:browserless)
        result = described_class.call(valid_config)

        expect(result).to have_attributes(
          success: true, item_count: 2, channel_title: 'Example', channel_url: 'https://example.com/news',
          strategy_used: :browserless, duration_seconds: 1.235, error_message: nil, failure_kind: nil,
          validation_issues: nil, enhance_compare: nil, response_body: '<html></html>'
        )
        expect(result.rss).to eq(fake_rss.to_s)
        expect(result.sample_items).to eq(
          [
            { title: 'First Example Article Title', url: 'https://example.com/news/1', published_at: nil },
            { title: 'Second Example Article Title', url: 'https://example.com/news/2', published_at: nil }
          ]
        )
      end

      it 'falls back to the configured strategy, then the default strategy name', :aggregate_failures do
        allow(fake_feed_result.status).to receive(:selected_strategy).and_return(nil)

        expect(described_class.call(valid_config.merge(strategy: :browserless)).strategy_used).to eq(:browserless)
        expect(described_class.call(valid_config).strategy_used).to eq(Html2rss::RequestService.default_strategy_name)
      end

      it 'samples at most three items with stripped titles and parsed dates', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        items = Array.new(4) do |index|
          instance_double(RSS::Rss::Channel::Item, title: "  Story number #{index} here  ",
                                                   link: "https://example.com/news/#{index}",
                                                   pubDate: Time.utc(2024, 1, 2, 3, 4, 5))
        end
        allow(fake_rss).to receive(:items).and_return(items)
        result = described_class.call(valid_config)

        expect(result.item_count).to eq(4)
        expect(result.sample_items.map { _1[:title] }).to eq(
          ['Story number 0 here', 'Story number 1 here', 'Story number 2 here']
        )
        expect(result.sample_items.first).to eq(
          title: 'Story number 0 here', url: 'https://example.com/news/0', published_at: DateTime.new(2024, 1, 2, 3, 4,
                                                                                                      5)
        )
      end

      it 'passes the strategy override and non-empty params to the pipeline', :aggregate_failures do
        described_class.call(valid_config, strategy: 'default', params: { 'q' => 'x' })

        expect(Html2rss::FeedPipeline).to have_received(:new).with(hash_including(strategy: :default,
                                                                                  params: { 'q' => 'x' }))
      end

      it 'leaves strategy and params out of the pipeline config when not given', :aggregate_failures do
        described_class.call(valid_config, params: {})

        expect(Html2rss::FeedPipeline).to have_received(:new).with(satisfy { |raw|
          !raw.key?(:strategy) && !raw.key?(:params)
        })
      end

      it 'probes for a native feed at channel.url using a diagnostic request session', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        allow(Html2rss::RequestSession).to receive(:build).and_call_original
        described_class.call(valid_config.merge(strategy: :default))

        expect(Html2rss::RequestSession).to have_received(:build).with(hash_including(strategy: :default))
        expect(Html2rss::Syndication::Discovery).to have_received(:best_feed_url).with(
          page_url: 'https://example.com/news', request_session: kind_of(Html2rss::RequestSession)
        )
      end

      it 'treats a discovery error as no native feed', :aggregate_failures do
        allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_raise(Html2rss::Error, 'boom')
        result = described_class.call(valid_config)

        expect(result.success).to be(true)
        expect(result.quality_report.native_feed).to be_nil
      end

      it 'reports the exact result when execution fails', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(10.0, 12.34567)
        allow(Html2rss::FeedPipeline).to receive(:new).and_raise(Html2rss::Error, 'network failure')
        result = described_class.call(valid_config.merge(strategy: :default))

        expect(result).to have_attributes(
          success: false, item_count: 0, sample_items: [], channel_title: 'Example',
          channel_url: 'https://example.com/news', strategy_used: :default, duration_seconds: 2.346,
          validation_issues: nil, error_message: 'Html2rss::Error: network failure',
          failure_kind: Html2rss::Test::FailureKind[:execution], rss: nil, quality_report: nil,
          enhance_compare: nil, response_body: nil
        )
      end

      describe 'url mismatch detection' do # rubocop:disable RSpec/NestedGroups
        it 'falls back to the entry url when the scrape url is empty', :aggregate_failures do
          allow(fake_feed_result.status).to receive_messages(scrape_url: '', entry_url: 'https://example.com/other')
          result = described_class.call(valid_config)

          expect(result.quality_report.warnings).to include(:url_mismatch)
          expect(result.quality_report.metrics[:url_mismatch]).to be(true)
        end

        it 'does not warn when the final url is the same document', :aggregate_failures do
          allow(fake_feed_result.status).to receive(:scrape_url).and_return('https://example.com/news#top')
          result = described_class.call(valid_config)

          expect(result.quality_report.warnings).not_to include(:url_mismatch)
          expect(result.quality_report.metrics).not_to have_key(:url_mismatch)
        end

        it 'does not warn when both final urls are empty' do
          allow(fake_feed_result.status).to receive_messages(scrape_url: '', entry_url: '')

          expect(described_class.call(valid_config).quality_report.warnings).not_to include(:url_mismatch)
        end

        it 'does not warn when the final url is unparsable' do
          allow(fake_feed_result.status).to receive(:scrape_url).and_return('not a url')

          expect(described_class.call(valid_config).quality_report.warnings).not_to include(:url_mismatch)
        end
      end

      it 'handles file path input' do
        result = described_class.call('spec/fixtures/single.test.yml')
        expect(result.valid_schema?).to be(true)
      end

      it 'handles YAML string input' do
        result = described_class.call(Html2rss::Config.to_yaml(valid_config))
        expect(result.valid_schema?).to be(true)
      end
    end

    context 'when YAML cannot be parsed' do
      it 'returns a schema failure without raising', :aggregate_failures do
        result = described_class.call("- items\n")
        expect(result.success).to be(false)
        expect(result.validation_issues).to include(
          an_object_having_attributes(code: :parse)
        )
      end
    end

    context 'when live extraction raises an error' do
      before do
        pipeline = instance_double(Html2rss::FeedPipeline)
        allow(pipeline).to receive(:to_outcome_and_result).and_raise(Html2rss::Error, 'network failure')
        allow(Html2rss::FeedPipeline).to receive(:new).and_return(pipeline)
      end

      it 'returns a failed Test::Result with error message', :aggregate_failures do
        result = described_class.call(valid_config)
        expect(result.success).to be(false)
        expect(result.error_message).to include('network failure')
        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind[:execution])
        expect(result.response_body).to be_nil
      end
    end

    context 'when enhance audit is enabled' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- fixture + pipeline outcome setup
      let(:fixture_body) { File.read(File.expand_path('../../fixtures/enhance_audit/rich_card.html', __dir__)) }
      let(:pipeline_response) do
        Html2rss::RequestService::Response.new(
          url: 'https://example.com/news',
          headers: { 'content-type' => 'text/html' },
          body: fixture_body
        )
      end
      let(:enhance_config) do
        valid_config.merge(
          selectors: {
            items: { selector: 'article.card', enhance: true },
            title: { selector: 'h2' },
            url: { selector: 'a', extractor: 'href' }
          }
        )
      end
      let(:pipeline_outcome) do
        Html2rss::FeedPipeline::PipelineOutcome.new(
          response: pipeline_response,
          articles: [],
          dedup_dropped: 0,
          selected_strategy: :default,
          attempt_count: 0,
          strategy_attempts: [],
          admission_drops: {},
          scrape_target: nil,
          entry_resolution: nil
        )
      end

      before do
        pipeline = instance_double(Html2rss::FeedPipeline, to_outcome_and_result: [pipeline_outcome, fake_feed_result])
        allow(Html2rss::FeedPipeline).to receive(:new).and_return(pipeline)
        allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_return(nil)
      end

      it 'includes enhance_gains in quality_report metrics', :aggregate_failures do
        result = described_class.call(enhance_config, min_items: 1)

        expect(result.quality_report.metrics[:enhance_gains]).to include(
          descriptions_added: be >= 1,
          no_op: false
        )
      end
    end

    context 'when compare_enhance is enabled' do # rubocop:disable RSpec/MultipleMemoizedHelpers -- fixture + pipeline outcome setup
      let(:fixture_body) { File.read(File.expand_path('../../fixtures/enhance_audit/rich_card.html', __dir__)) }
      let(:pipeline_response) do
        Html2rss::RequestService::Response.new(
          url: 'https://example.com/news',
          headers: { 'content-type' => 'text/html' },
          body: fixture_body
        )
      end
      let(:compare_config) do
        valid_config.merge(
          selectors: {
            items: { selector: 'article.card', enhance: false },
            title: { selector: 'h2' },
            url: { selector: 'a', extractor: 'href' }
          }
        )
      end
      let(:pipeline_outcome) do
        Html2rss::FeedPipeline::PipelineOutcome.new(
          response: pipeline_response,
          articles: [],
          dedup_dropped: 0,
          selected_strategy: :default,
          attempt_count: 0,
          strategy_attempts: [],
          admission_drops: {},
          scrape_target: nil,
          entry_resolution: nil
        )
      end

      before do
        pipeline = instance_double(Html2rss::FeedPipeline, to_outcome_and_result: [pipeline_outcome, fake_feed_result])
        allow(Html2rss::FeedPipeline).to receive(:new).and_return(pipeline)
        allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_return(nil)
      end

      it 'includes enhance_compare on the result', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        result = described_class.call(compare_config, min_items: 1, compare_enhance: true)

        expect(result.enhance_compare).to include(
          enhance_off: hash_including(item_count: 2),
          enhance_on: hash_including(descriptions_filled: be >= 1),
          delta: hash_including(descriptions_gained: be >= 1, no_op: false)
        )
        expect(result.quality_report.metrics).not_to have_key(:enhance_gains)
        expect(result.to_h).to include(enhance_compare: result.enhance_compare)
      end
    end
  end
end
