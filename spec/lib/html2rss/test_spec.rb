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
        items: { selector: 'article' },
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

  let(:fake_rss_item) do
    instance_double(
      RSS::Rss::Channel::Item,
      title: 'Article 1',
      link: 'https://example.com/news/1',
      pubDate: nil
    )
  end

  let(:fake_rss) do
    instance_double(RSS::Rss, items: [fake_rss_item])
  end

  let(:fake_feed_result) do
    instance_double(
      Html2rss::FeedResult,
      to_rss: fake_rss,
      channel_title: 'Example',
      status: instance_double(Html2rss::Status, selected_strategy: :faraday)
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
        allow(Html2rss).to receive(:feed_result).and_return(fake_feed_result)
      end

      it 'returns a successful Test::Result with article count, samples, and rss', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        result = described_class.call(valid_config, min_items: 1)
        expect(result.success).to be(true)
        expect(result.item_count).to eq(1)
        expect(result.sample_items.size).to eq(1)
        expect(result.rss).to be_a(String)
        expect(result.failure_kind).to be_nil
      end

      it 'fails if extracted items are below min_items', :aggregate_failures do
        result = described_class.call(valid_config, min_items: 5)
        expect(result.success).to be(false)
        expect(result.error_message).to include('Extracted 1 items (minimum required: 5)')
        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind.coerce(:min_items))
        expect(result.rss).to be_nil
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
        allow(Html2rss).to receive(:feed_result).and_raise(RuntimeError, 'network failure')
      end

      it 'returns a failed Test::Result with error message', :aggregate_failures do
        result = described_class.call(valid_config)
        expect(result.success).to be(false)
        expect(result.error_message).to include('network failure')
        expect(result.failure_kind).to eq(Html2rss::Test::FailureKind.coerce(:execution))
      end
    end
  end
end
