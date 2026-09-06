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
        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind.coerce(:schema))
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
        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind.coerce(:min_items))
        expect(result.rss).to be_nil
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
        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind.coerce(:quality))
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
        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind.coerce(:quality))
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

        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind.coerce(:min_items))
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
        expect(result.validation_errors).to have_key(:parse)
      end
    end

    context 'when live extraction raises an error' do
      before do
        pipeline = instance_double(Html2rss::FeedPipeline)
        allow(pipeline).to receive(:to_outcome_and_result).and_raise(RuntimeError, 'network failure')
        allow(Html2rss::FeedPipeline).to receive(:new).and_return(pipeline)
      end

      it 'returns a failed Test::Result with error message', :aggregate_failures do
        result = described_class.call(valid_config)
        expect(result.success).to be(false)
        expect(result.error_message).to include('network failure')
        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind.coerce(:execution))
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
