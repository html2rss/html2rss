# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength

RSpec.describe Html2rss::Curation::Test::Quality do
  let(:vocabulary) { Html2rss::Vocabulary[nil] }
  let(:valid_config) do
    {
      channel: { title: 'Example', url: 'https://example.com/news', time_zone: 'UTC' },
      selectors: {
        items: { selector: 'article', enhance: false },
        title: { selector: 'h2' },
        url: { selector: 'a', extractor: 'href' }
      }
    }
  end
  let(:fake_rss_items) do
    %w[First Second].each_with_index.map do |name, index|
      instance_double(RSS::Rss::Channel::Item, description: nil, title: "#{name} Example Article Title",
                                               link: "https://example.com/news/#{index + 1}", pubDate: nil)
    end
  end

  describe '.audit' do
    it 'returns no warnings for a clean multi-item feed', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      items = [
        rss_item(title: 'First Article Title Here', url: 'https://example.com/a'),
        rss_item(title: 'Second Article Title Here', url: 'https://example.com/b')
      ]
      audit = described_class.audit(items, vocabulary:)

      expect(audit.warnings).to be_empty
      expect(audit.metrics).to include(item_count: 2, unique_url_count: 2, junk_title_count: 0)
    end

    it 'warns on duplicate URLs', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      items = [
        rss_item(title: 'Story One Title Here', url: 'https://example.com/same'),
        rss_item(title: 'Story Two Title Here', url: 'https://example.com/same')
      ]
      audit = described_class.audit(items, vocabulary:)

      expect(audit.warnings).to include(:duplicate_urls)
      expect(audit.metrics[:junk_title_count]).to eq(0)
    end

    it 'warns on duplicate URLs that differ only by scheme, tracking params, or trailing slash' do
      items = %w[http://example.com/same https://example.com/same/?utm_source=x].map do |href|
        rss_item(title: 'Story Title Words Here', url: href)
      end

      expect(described_class.audit(items, vocabulary:).warnings).to include(:duplicate_urls)
    end

    it 'counts fragment-only variants of one URL as a duplicate', :aggregate_failures do
      items = [rss_item(title: 'Story One Title Here', url: 'https://example.com/same#top'),
               rss_item(title: 'Story Two Title Here', url: 'https://example.com/same')]
      audit = described_class.audit(items, vocabulary:)

      expect(audit.metrics[:unique_url_count]).to eq(1)
      expect(audit.warnings).to include(:duplicate_urls)
    end

    it 'warns on CTA titles', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      items = [
        rss_item(title: 'Read More', url: 'https://example.com/a'),
        rss_item(title: 'Valid Article Title Here', url: 'https://example.com/b')
      ]
      audit = described_class.audit(items, vocabulary:)

      expect(audit.warnings).to include(:generic_titles)
      expect(audit.metrics[:junk_title_count]).to eq(1)
    end

    it 'warns on short titles', :aggregate_failures do
      audit = described_class.audit([rss_item(title: 'Ok', url: 'https://example.com/a')], vocabulary:)

      expect(audit.warnings).to include(:short_titles, :low_word_count)
      expect(audit.metrics[:junk_title_count]).to eq(0)
    end

    it 'reports duplicate, short and low-word findings with exact, frozen metrics', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      items = [
        rss_item(title: 'Ok', url: 'https://example.com/a'),
        rss_item(title: 'Story Two Title Here', url: 'https://example.com/a')
      ]
      audit = described_class.audit(items, vocabulary:)

      expect(audit.warnings).to eq(%i[duplicate_urls short_titles low_word_count])
      expect(audit.metrics).to eq(item_count: 2, unique_url_count: 1, junk_title_count: 0,
                                  short_title_count: 1, low_word_count: 1,
                                  run_together_title_count: 0, list_description_count: 0)
      expect(audit.metrics).to be_frozen
    end

    context 'with navigation-menu items' do
      def described_item(title, description, index)
        instance_double(RSS::Rss::Channel::Item, title:, description:, link: "https://example.com/n/#{index}")
      end

      let(:menu_items) do
        [['VisitOpening HoursReaching usMap', '<ul><li>Hours</li><li>Tickets</li><li>Parking</li></ul>'],
         ['EventsTicketsGroupsShopDonate', '<ul><li>Events</li><li>Shop</li><li>Donate</li></ul>']]
          .each_with_index.map { |(title, html), index| described_item(title, html, index) }
      end

      it 'warns on run-together titles and list descriptions', :aggregate_failures do
        audit = described_class.audit(menu_items, vocabulary:)

        expect(audit.warnings).to include(:run_together_titles, :list_descriptions)
        expect(audit.metrics).to include(run_together_title_count: 2, list_description_count: 2)
      end

      it 'counts bullet-marker text lines as a list description' do
        text = "Menu\n• Hours\n• Tickets\n- Parking"
        items = [described_item('First Story Title Here', text, 1), described_item('Second Story Title Here', text, 2)]

        expect(described_class.audit(items, vocabulary:).warnings).to eq([:list_descriptions])
      end

      it 'stays quiet for camelCase brands and prose descriptions', :aggregate_failures do
        prose = '<p>The launch drew crowds.</p><ul><li>One</li></ul><p>Sales rose in the third quarter.</p>'
        items = ['iPhone launch', "McDonald's results"].each_with_index.map do |title, index|
          described_item(title, prose, index)
        end
        audit = described_class.audit(items, vocabulary:)

        expect(audit.warnings).not_to include(:run_together_titles, :list_descriptions)
        expect(audit.metrics).to include(run_together_title_count: 0, list_description_count: 0)
      end

      it 'does not warn for a single menu-like item', :aggregate_failures do
        audit = described_class.audit([menu_items.first], vocabulary:)

        expect(audit.warnings).to be_empty
      end
    end

    it 'does not warn about duplicate URLs for a single item', :aggregate_failures do
      audit = described_class.audit([rss_item(title: 'Single Article Title', url: 'https://example.com/a')],
                                    vocabulary:)

      expect(audit.warnings).not_to include(:duplicate_urls)
      expect(audit.metrics[:unique_url_count]).to eq(1)
    end

    it 'does not count items without a URL as unique', :aggregate_failures do
      items = [rss_item(title: 'First Article Title Here', url: nil),
               rss_item(title: 'Second Article Title Here', url: nil)]
      audit = described_class.audit(items, vocabulary:)

      expect(audit.metrics).to include(item_count: 2, unique_url_count: 0)
      expect(audit.warnings).to include(:duplicate_urls)
    end

    it 'counts a junk title and a low word count separately', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      items = [
        rss_item(title: 'Read More', url: 'https://example.com/a'),
        rss_item(title: 'Two Words', url: 'https://example.com/b')
      ]
      audit = described_class.audit(items, vocabulary:)

      expect(audit.metrics).to include(junk_title_count: 1, low_word_count: 1, short_title_count: 0)
      expect(audit.warnings).to eq(%i[generic_titles low_word_count])
    end

    it 'freezes the warnings and reads the URL out of a link with surrounding text', :aggregate_failures do
      audit = described_class.audit([rss_item(title: 'Story Title Words Here', url: 'see https://example.com/a')],
                                    vocabulary:)

      expect(audit.warnings).to be_frozen
      expect(audit.metrics[:unique_url_count]).to eq(1)
    end

    it 'skips blank titles and collapses whitespace like the feed item', :aggregate_failures do
      items = [rss_item(title: "  \n ", url: 'https://example.com/a'),
               rss_item(title: " Read \n more ", url: 'https://example.com/b')]
      audit = described_class.audit(items, vocabulary:)

      expect(audit.metrics).to include(junk_title_count: 1, short_title_count: 0, low_word_count: 0)
    end
  end

  describe '.failure_reasons' do
    {
      'clean metrics' => [{}, []],
      'zero items' => [{ item_count: 0, unique_url_count: 0, junk_title_count: 0, short_title_count: 0 }, []],
      'two items sharing a url' => [{ item_count: 2, unique_url_count: 1 }, [:duplicate_urls]],
      'two items with distinct urls' => [{ item_count: 2, unique_url_count: 2 }, []],
      'one item with one url' => [{ item_count: 1, unique_url_count: 1 }, []],
      'exactly half junk titles' => [{ junk_title_count: 2 }, []],
      'more than half junk titles' => [{ junk_title_count: 3 }, [:generic_titles]],
      'one short title' => [{ short_title_count: 1 }, [:short_titles]],
      'few junk titles among many items' => [{ item_count: 10, unique_url_count: 10, junk_title_count: 3 }, []],
      'every reason, in order' => [{ unique_url_count: 1, junk_title_count: 3, short_title_count: 1 },
                                   %i[duplicate_urls generic_titles short_titles]]
    }.each do |label, (overrides, expected)|
      it "is #{expected.inspect} for #{label}" do
        expect(described_class.failure_reasons(quality_report_with(**overrides).metrics)).to eq(expected)
      end
    end
  end

  describe '.report_for' do
    let(:enhance) { true }
    let(:config) do
      Html2rss::Config.from_hash(
        valid_config.merge(
          selectors: valid_config[:selectors].merge(items: { selector: 'article', enhance: })
        )
      )
    end
    let(:response) do
      Html2rss::RequestService::Response.new(url: 'https://example.com/news', headers: {}, body: '<html></html>')
    end
    let(:pipeline_outcome) { instance_double(Html2rss::FeedPipeline::PipelineOutcome, response:, admission_drops: {}) }
    let(:status) { instance_double(Html2rss::Status, scrape_url: 'https://example.com/news', entry_url: '') }
    let(:feed_result) { instance_double(Html2rss::FeedResult, status:) }
    let(:slice) do
      gains = Html2rss::Curation::Test::EnhanceAudit::EnhanceGains.new(
        items_probed: 2, keys_added: { title: 1 }, descriptions_added: 3, no_op: false
      )
      Html2rss::Curation::Test::EnhanceAudit::AuditSlice.new(enhance_gains: gains, warnings: %i[w_one duplicate_urls])
    end
    let(:probed) { slice }
    let(:channel_url) { 'https://example.com/news' }
    let(:report) do
      described_class.report_for(
        fake_rss_items, channel_url:, config:, feed_result:, pipeline_outcome:, probe_native_feed: false
      )
    end

    before do
      allow(Html2rss::Curation::Test::EnhanceAudit).to receive(:probe).and_return(probed)
      allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_return(nil)
    end

    it 'merges enhance warnings once and reports the gains', :aggregate_failures do
      allow(fake_rss_items.last).to receive(:link).and_return(fake_rss_items.first.link)

      expect(report.warnings).to eq(%i[duplicate_urls w_one])
      expect(report.metrics[:enhance_gains]).to eq(items_probed: 2, keys_added: { title: 1 }, descriptions_added: 3,
                                                   no_op: false)
      expect(report.warnings).to be_frozen
    end

    it 'probes with the response, selectors and time zone', :aggregate_failures do
      report

      expect(Html2rss::Curation::Test::EnhanceAudit).to have_received(:probe).with(
        response:, selectors: config.selectors, time_zone: 'UTC', vocabulary: Html2rss::Vocabulary[nil]
      )
      expect(Html2rss::Syndication::Discovery).not_to have_received(:best_feed_url)
    end

    context 'when the channel overrides the page language' do
      let(:config) do
        Html2rss::Config.from_hash(
          valid_config.merge(
            channel: valid_config[:channel].merge(language: 'zh-Hant'),
            selectors: valid_config[:selectors].merge(items: { selector: 'article', enhance: })
          )
        )
      end

      it 'probes with the scope the feed reads', :aggregate_failures do
        report

        expect(Html2rss::Curation::Test::EnhanceAudit).to have_received(:probe).with(
          hash_including(vocabulary: be(Html2rss::Vocabulary[:zh]))
        )
      end

      it 'counts a Chinese read-more item title as junk, as the feed itself reads it', :aggregate_failures do
        read_more = instance_double(RSS::Rss::Channel::Item, description: nil, title: '了解更多', link: 'https://example.com/news/3',
                                                             pubDate: nil)
        result = described_class.report_for(
          fake_rss_items + [read_more], channel_url:, config:, feed_result:, pipeline_outcome:,
                                        probe_native_feed: false
        )

        expect(result.metrics[:junk_title_count]).to eq(1)
      end
    end

    context 'when enhance is disabled' do
      let(:enhance) { false }

      it 'does not probe', :aggregate_failures do
        expect(report.metrics).not_to have_key(:enhance_gains)
        expect(Html2rss::Curation::Test::EnhanceAudit).not_to have_received(:probe)
      end
    end

    context 'when the config has no selectors' do
      let(:config) do
        Html2rss::Config.from_hash(valid_config.except(:selectors).merge(auto_source: {}))
      end

      it 'skips enhance auditing', :aggregate_failures do
        expect(report.metrics).not_to have_key(:enhance_gains)
        expect(Html2rss::Curation::Test::EnhanceAudit).not_to have_received(:probe)
      end
    end

    context 'when the probe yields nothing' do
      let(:probed) { nil }

      it 'returns the plain report', :aggregate_failures do
        expect(report.warnings).to eq([])
        expect(report.metrics).not_to have_key(:enhance_gains)
      end
    end

    context 'when judging the final url' do
      it 'falls back to the entry url when the scrape url is empty', :aggregate_failures do
        allow(status).to receive_messages(scrape_url: '', entry_url: 'https://example.com/other')

        expect(report.warnings).to include(:url_mismatch)
        expect(report.metrics[:url_mismatch]).to be(true)
      end

      it 'reads url objects and a missing scrape url like strings', :aggregate_failures do
        allow(status).to receive_messages(scrape_url: nil, entry_url: Html2rss::Url.from_absolute('https://example.com/o'))

        expect(report.warnings).to include(:url_mismatch)
      end

      it 'does not warn when the final url is the same document', :aggregate_failures do
        allow(status).to receive(:scrape_url).and_return('https://example.com/news#top')

        expect(report.warnings).not_to include(:url_mismatch)
        expect(report.metrics).not_to have_key(:url_mismatch)
      end

      it 'does not warn when both final urls are empty' do
        allow(status).to receive_messages(scrape_url: '', entry_url: nil)

        expect(report.warnings).not_to include(:url_mismatch)
      end

      it 'does not warn when the final url is unparsable' do
        allow(status).to receive(:scrape_url).and_return('not a url')

        expect(report.warnings).not_to include(:url_mismatch)
      end

      it 'does not warn without a configured channel url' do
        allow(status).to receive(:scrape_url).and_return('https://example.com/elsewhere')
        blank = described_class.report_for(fake_rss_items, channel_url: '', config:, feed_result:, pipeline_outcome:,
                                                           probe_native_feed: false)

        expect(blank.warnings).not_to include(:url_mismatch)
      end
    end

    context 'when probing for a native feed' do
      let(:config) do
        Html2rss::Config.from_hash(valid_config.merge(strategy: :browserless))
      end
      let(:probing_report) do
        described_class.report_for(fake_rss_items, channel_url:, config:, feed_result:, pipeline_outcome:)
      end

      it 'reads the fetched channel page with a diagnostic request session', :aggregate_failures do
        allow(Html2rss::RequestSession).to receive(:build).and_call_original
        probing_report

        expect(Html2rss::RequestSession).to have_received(:build).with(
          hash_including(strategy: :browserless, budget: kind_of(Html2rss::RequestService::Budget),
                         policy: kind_of(Html2rss::RequestService::Policy))
        )
        expect(Html2rss::Syndication::Discovery).to have_received(:best_feed_url).with(
          page_url: 'https://example.com/news', request_session: kind_of(Html2rss::RequestSession),
          parsed_body: kind_of(Nokogiri::HTML::Document), html: '<html></html>'
        )
      end

      it 'probes an automatic strategy with the default one', :aggregate_failures do
        allow(Html2rss::RequestSession).to receive(:build).and_call_original
        described_class.report_for(fake_rss_items, channel_url:, config: Html2rss::Config.from_hash(valid_config),
                                                   feed_result:, pipeline_outcome:)

        expect(Html2rss::RequestSession).to have_received(:build)
          .with(hash_including(strategy: Html2rss::RequestService.default_strategy_name))
      end

      it 'treats a discovery error as no native feed' do
        allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_raise(Html2rss::Error, 'boom')

        expect(probing_report.native_feed).to be_nil
      end

      it 'propagates a discovery contract error' do
        allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url)
          .and_raise(Html2rss::RequestService::Context::InvalidError)

        expect { probing_report }.to raise_error(Html2rss::ContractError)
      end

      it 'skips discovery without a configured channel url', :aggregate_failures do
        blank = described_class.report_for(fake_rss_items, channel_url: '', config:, feed_result:, pipeline_outcome:)

        expect(blank.native_feed).to be_nil
        expect(Html2rss::Syndication::Discovery).not_to have_received(:best_feed_url)
      end
    end

    context 'when a native feed exists and the url mismatches' do
      let(:native) { Html2rss::Url.from_absolute('https://example.com/feed.xml') }

      before do
        allow(status).to receive(:scrape_url).and_return('https://example.com/elsewhere')
        allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_return(native)
      end

      it 'keeps the native feed through the url mismatch and enhance merges', :aggregate_failures do
        result = described_class.report_for(
          fake_rss_items, channel_url:, config:, feed_result:, pipeline_outcome:
        )

        expect(result).to have_attributes(
          warnings: %i[native_feed_present url_mismatch w_one duplicate_urls],
          native_feed: 'https://example.com/feed.xml', defer_reason: :native_feed
        )
        expect(result.metrics).to include(url_mismatch: true, enhance_gains: hash_including(items_probed: 2))
      end

      it 'does not duplicate warnings that are already present', :aggregate_failures do
        allow(Html2rss::Curation::Test::EnhanceAudit).to receive(:probe).and_return(
          slice.with(warnings: %i[native_feed_present url_mismatch])
        )
        result = described_class.report_for(
          fake_rss_items, channel_url:, config:, feed_result:, pipeline_outcome:
        )

        expect(result.warnings).to eq(%i[native_feed_present url_mismatch])
      end
    end

    context 'when the fetched page names no native feed' do
      it 'probes that page and reports no native feed', :aggregate_failures do
        result = described_class.report_for(fake_rss_items, channel_url:, config:, feed_result:,
                                                            pipeline_outcome:)

        expect(result).to have_attributes(native_feed: nil, defer_reason: nil)
        expect(Html2rss::Syndication::Discovery).to have_received(:best_feed_url).with(
          page_url: channel_url, request_session: kind_of(Html2rss::RequestSession),
          parsed_body: kind_of(Nokogiri::HTML::Document), html: '<html></html>'
        )
      end
    end

    context 'when the channel url is empty' do
      let(:channel_url) { '' }

      it 'skips native feed discovery', :aggregate_failures do
        described_class.report_for(fake_rss_items, channel_url:, config:, feed_result:, pipeline_outcome:)

        expect(Html2rss::Syndication::Discovery).not_to have_received(:best_feed_url)
      end
    end

    describe '.append_items_without_url_warning' do
      let(:native) { Html2rss::Url.from_absolute('https://example.com/feed.xml') }
      let(:pipeline_outcome) do
        instance_double(Html2rss::FeedPipeline::PipelineOutcome, response:, admission_drops: { 'missing_url' => 2 })
      end

      before { allow(Html2rss::Syndication::Discovery).to receive(:best_feed_url).and_return(native) }

      it 'adds the warning and count to the report and keeps the rest of it', :aggregate_failures do
        result = described_class.report_for(fake_rss_items, channel_url:, config:, feed_result:,
                                                            pipeline_outcome:)

        expect(result).to have_attributes(
          warnings: %i[native_feed_present items_without_url w_one duplicate_urls],
          native_feed: 'https://example.com/feed.xml', defer_reason: :native_feed
        )
        expect(result.warnings).to be_frozen
        expect(result.metrics).to include(items_without_url: 2)
      end

      context 'when enhance is off' do # rubocop:disable RSpec/NestedGroups
        let(:enhance) { false }

        it 'returns a frozen warnings list' do
          result = described_class.report_for(fake_rss_items, channel_url:, config:, feed_result:,
                                                              pipeline_outcome:)

          expect(result.warnings).to be_frozen
        end
      end

      it 'ignores other drop reasons', :aggregate_failures do
        allow(pipeline_outcome).to receive(:admission_drops).and_return('sponsored' => 4)
        result = described_class.report_for(fake_rss_items, channel_url:, config:, feed_result:,
                                                            pipeline_outcome:)

        expect(result.warnings).not_to include(:items_without_url)
        expect(result.metrics).not_to have_key(:items_without_url)
      end
    end
  end

  describe 'Navigation' do
    let(:navigation) { described_class::Navigation }

    it 'needs three lowercase-to-uppercase joins for a run-together title', :aggregate_failures do
      expect(navigation.run_together_title?('VisitOpening HoursReaching usMap')).to be(true)
      expect(navigation.run_together_title?('aBcDeF')).to be(true)
      expect(navigation.run_together_title?('iPhone McDonald')).to be(false)
      expect(navigation.run_together_title?('ABC DEF GHI')).to be(false)
      expect(navigation.run_together_title?('')).to be(false)
    end

    it 'needs three list lines and a majority for a list description', :aggregate_failures do
      expect(navigation.list_description?('<ul><li>a</li><li>b</li><li>c</li></ul>')).to be(true)
      expect(navigation.list_description?("- a\n* b\n• c")).to be(true)
      expect(navigation.list_description?("· a\n▪ b\n‣ c")).to be(true)
      expect(navigation.list_description?('<ul><li>a</li><li>b</li></ul>')).to be(false)
      expect(navigation.list_description?("x\ny\nz\n- a\n- b\n- c")).to be(false)
      expect(navigation.list_description?("x\n- a\n- b\n- c")).to be(true)
      expect(navigation.list_description?('-a -b -c')).to be(false)
      expect(navigation.list_description?(nil)).to be(false)
      expect(navigation.list_description?("  - a\n\n\n  - b\n\n\n  - c")).to be(true)
      expect(navigation.list_description?("-\n-\n-")).to be(false)
      expect(navigation.list_description?("- a\n- b\n- c\n- d")).to be(true)
    end

    it 'counts the items that carry a list description' do
      list = instance_double(RSS::Rss::Channel::Item, description: '<ul><li>a</li><li>b</li><li>c</li></ul>')
      prose = instance_double(RSS::Rss::Channel::Item, description: '<p>Prose</p>')

      expect(navigation.list_description_count([list, prose, list])).to eq(2)
    end

    it 'warns from two items and half the item count', :aggregate_failures do
      expect(navigation.share?({ item_count: 4, sign: 2 }, :sign)).to be(true)
      expect(navigation.share?({ item_count: 5, sign: 2 }, :sign)).to be(false)
      expect(navigation.share?({ item_count: 1, sign: 1 }, :sign)).to be(false)
      expect(navigation.share?({ item_count: 2, sign: 2 }, :sign)).to be(true)
      expect(navigation.share?({ item_count: 4, sign: 3 }, :sign)).to be(true)
    end
  end
end

# rubocop:enable RSpec/MultipleMemoizedHelpers, RSpec/ExampleLength
