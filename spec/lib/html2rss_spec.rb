# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss do
  let(:config_file) { File.join(%w[spec fixtures feeds.test.yml]) }
  let(:name) { 'nuxt-releases' }

  it 'has a version number' do
    expect(Html2rss::VERSION).not_to be_nil
  end

  describe '.config_from_yaml_file(file, feed_name = nil)' do
    subject(:feed) do
      described_class.config_from_yaml_file(config_file, name)
    end

    context 'with known name' do
      it { expect(feed).to be_a(Hash) }
    end

    context 'with unknown name' do
      it 'raises an ArgumentError' do
        expect { described_class.config_from_yaml_file(config_file, 'unknown') }.to raise_error(ArgumentError)
      end
    end
  end

  describe '.feed' do
    context 'with config being a Hash' do
      subject(:xml) { Nokogiri.XML(feed_return.to_s) }

      let(:config) do
        described_class.config_from_yaml_file(config_file, name)
      end
      let(:feed_return) { VCR.use_cassette(name) { described_class.feed(config) } }

      before do
        allow(Faraday).to receive(:new).with(Hash).and_call_original
      end

      it 'returns a RSS::Rss instance & sets the request headers', :aggregate_failures do
        expect(feed_return).to be_a(RSS::Rss)
        expect(Faraday).to have_received(:new).with(
          hash_including(headers: hash_including(config[:headers].transform_keys(&:to_s)))
        )
      end

      describe 'feed.channel' do
        it 'sets the channel attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
          expect(xml.css('channel > title').text).to eq 'Releases · nuxt/nuxt.js · GitHub'
          expect(xml.css('channel > description').text).to \
            eq('The Vue.js Framework. Contribute to nuxt/nuxt.js development by creating an account on GitHub.')
          expect(xml.css('channel > ttl').text.to_i).to eq 0
          expect(xml.css('channel > item').count).to be > 0
          expect(xml.css('channel > link').text).to eq 'https://github.com/nuxt/nuxt.js/releases'
          expect(xml.css('channel > generator').text).to start_with("html2rss V. #{Html2rss::VERSION}")
        end
      end

      describe 'feed.items' do
        subject(:item) { xml.css('channel > item').first }

        it 'sets item attributes', :aggregate_failures do
          expect(item.css('title').text).to eq 'v2.10.2 (pi)'
          expect(item.css('link').text).to eq 'https://github.com/nuxt/nuxt.js/releases/tag/v2.10.2'
          expect(item.css('author').text).to eq 'pi'
          expect(item.css('guid').text).to eq 'resdti'
        end

        describe 'item.pubDate' do
          it 'has one in rfc822 format' do
            pub_date = item.css('pubDate').text
            expect(pub_date).to be_a(String) & eq(Time.parse(pub_date).rfc822.to_s)
          end
        end

        describe 'item.category' do
          subject(:categories) { item.css('category').to_s }

          it 'sets the author as category' do
            expect(categories).to include '<category>pi</category>'
          end
        end

        describe 'item.enclosure' do
          subject(:enclosure) { item.css('enclosure') }

          it 'sets the enclosure', :aggregate_failures do
            expect(enclosure.attr('url').value).to start_with('https://'), 'url'
            expect(enclosure.attr('type').value).to eq('application/octet-stream'), 'type'
            expect(enclosure.attr('length').value).to eq('0'), 'length'
          end
        end

        describe 'item.description' do
          subject(:description) { item.css('description').text }

          it 'has a description' do
            expect(description).to be_a(String)
          end

          it 'adds rel="nofollow noopener noreferrer" to all anchor elements' do
            Nokogiri.HTML(description).css('a').each do |anchor|
              expect(anchor.attr('rel')).to eq 'nofollow noopener noreferrer'
            end
          end

          it 'changes target="_blank" on all anchor elements' do
            Nokogiri.HTML(description).css('a').each { |anchor| expect(anchor.attr('target')).to eq '_blank' }
          end
        end

        describe 'item.guid' do
          it 'stays the same string for each run' do
            feed = VCR.use_cassette("#{name}-second-run") do
              described_class.feed(config)
            end

            first_guid = feed.items.first.guid.content

            expect(feed_return.items.first.guid.content).to eq first_guid
          end

          it 'sets isPermaLink attribute to false' do
            expect(feed_return.items.first.guid.isPermaLink).to be false
          end
        end
      end

      context 'with items having order key and reverse as value' do
        before do
          config[:selectors][:items][:order] = 'reverse'
        end

        it 'reverses the item ordering' do
          expect(xml.css('channel > item').last.css('title').text).to eq 'v2.10.2 (pi)'
        end
      end
    end

    context 'with config having channel headers and header accepts json' do
      let(:feed) do
        VCR.use_cassette('httpbin-headers') do
          described_class.feed(feed_config)
        end
      end

      let(:feed_config) do
        {
          headers: {
            Accept: 'application/json',
            'User-Agent': 'html2rss-request',
            'X-Something': 'Foobar',
            Authorization: 'Token deadbea7',
            Cookie: 'monster=MeWantCookie'
          },
          channel: {
            url: 'https://httpbin.org/headers',
            title: 'httpbin headers'
          },
          selectors: {
            items: { selector: 'object > headers' },
            title: { selector: 'host' },
            something: { selector: 'x-something' },
            authorization: { selector: 'authorization' },
            cookie: { selector: 'cookie' },
            categories: %i[title something authorization cookie]
          }
        }
      end

      it 'converts response to xml which has the information', :aggregate_failures do
        expect(feed.items.size).to eq 1
        expect(feed.items.first.categories.map(&:content)).to include('httpbin.org', 'Foobar', 'Token deadbea7',
                                                                      'monster=MeWantCookie')
      end
    end

    context 'with config having selectors and is json response' do
      subject(:feed) do
        VCR.use_cassette(name) do
          config = described_class.config_from_yaml_file(config_file, name)
          described_class.feed(config)
        end
      end

      let(:name) { 'json' }

      context 'with returned config' do
        subject(:xml) { Nokogiri.XML(feed.to_s) }

        it 'has the description derived from markdown' do
          expect(
            xml.css('item > description').first.text
          ).to eq '<h1>JUDAS AND THE BLACK MESSIAH</h1> <p>MPAA rating: R</p>'
        end
      end
    end

    context 'with selectors.items pagination enabled' do
      subject(:feed) { described_class.feed(config) }

      let(:config) do
        {
          strategy: :faraday,
          channel: { url: 'https://example.com/news', title: 'Example News' },
          selectors: {
            items: { selector: 'article', pagination: { max_pages: 3 } },
            title: { selector: 'h1' }
          }
        }
      end

      before do
        allow(described_class).to receive(:build_rss_feed).and_call_original
        allow(Html2rss::RequestService).to receive(:execute).and_wrap_original do |_original, ctx, **_kwargs|
          ctx.budget.consume!

          case ctx.url.to_s
          when 'https://example.com/news'
            Html2rss::RequestService::Response.new(
              body: <<~HTML,
                <html><head><link rel="next" href="/news?page=2"></head><body><article><h1>page1</h1></article></body></html>
              HTML
              url: ctx.url,
              headers: { 'content-type' => 'text/html' }
            )
          when 'https://example.com/news?page=2'
            Html2rss::RequestService::Response.new(
              body: '<html><body><article><h1>page2</h1></article></body></html>',
              url: ctx.url,
              headers: { 'content-type' => 'text/html' }
            )
          else
            raise "Unexpected URL #{ctx.url}"
          end
        end
      end

      it 'collects items from pagination follow-up pages', :aggregate_failures do
        expect(feed.items.map(&:title)).to eq(%w[page1 page2])
        expect(Html2rss::RequestService).to have_received(:execute).twice
      end

      context 'when max_redirects is configured' do
        let(:config) do
          {
            strategy: :faraday,
            max_redirects: 8,
            channel: { url: 'https://example.com/news', title: 'Example News' },
            selectors: {
              items: { selector: 'article' },
              title: { selector: 'h1' }
            }
          }
        end

        it 'builds the request policy with the configured redirect limit', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
          feed

          expect(Html2rss::RequestService).to have_received(:execute).with(
            satisfy do |ctx|
              ctx.policy.max_redirects == 8 &&
                ctx.url.to_s == 'https://example.com/news'
            end,
            strategy: :faraday
          )
        end
      end

      context 'when max_requests is configured' do
        let(:config) do
          {
            strategy: :faraday,
            max_requests: 8,
            channel: { url: 'https://example.com/news', title: 'Example News' },
            selectors: {
              items: { selector: 'article' },
              title: { selector: 'h1' }
            }
          }
        end

        it 'builds the request policy with the configured request budget', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
          feed

          expect(Html2rss::RequestService).to have_received(:execute).with(
            satisfy do |ctx|
              ctx.policy.max_requests == 8 &&
                ctx.url.to_s == 'https://example.com/news'
            end,
            strategy: :faraday
          )
        end
      end

      context 'when the initial request redirects to a different host' do
        before do
          allow(Html2rss::RequestService).to receive(:execute).and_wrap_original do |_original, ctx, **_kwargs|
            ctx.budget.consume!

            case ctx.url.to_s
            when 'https://example.com/news'
              Html2rss::RequestService::Response.new(
                body: <<~HTML,
                  <html><head><link rel="next" href="/news?page=2"></head><body><article><h1>page1</h1></article></body></html>
                HTML
                url: Html2rss::Url.from_absolute('https://redirected.example.com/news'),
                headers: { 'content-type' => 'text/html' }
              )
            when 'https://redirected.example.com/news?page=2'
              Html2rss::RequestService::Response.new(
                body: '<html><body><article><h1>page2</h1></article></body></html>',
                url: ctx.url,
                headers: { 'content-type' => 'text/html' }
              )
            else
              raise "Unexpected URL #{ctx.url}"
            end
          end
        end

        it 'uses the redirected page as the origin for rel-next follow-ups', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
          expect(feed.items.map(&:title)).to eq(%w[page1 page2])
          expect(Html2rss::RequestService).to have_received(:execute).with(
            satisfy do |ctx|
              ctx.url.to_s == 'https://redirected.example.com/news?page=2' &&
                ctx.origin_url.to_s == 'https://redirected.example.com/news' &&
                ctx.relation == :pagination
            end,
            strategy: :faraday
          )
        end
      end

      context 'when max_pages exceeds the system pagination ceiling' do
        let(:config) do
          {
            strategy: :faraday,
            channel: { url: 'https://example.com/news', title: 'Example News' },
            selectors: {
              items: { selector: 'article', pagination: { max_pages: 20 } },
              title: { selector: 'h1' }
            }
          }
        end

        before do
          allow(Html2rss::RequestService).to receive(:execute).and_wrap_original do |_original, ctx, **_kwargs|
            ctx.budget.consume!

            page_number = ctx.url.query.to_s[/((?:^|&)page=)(\d+)/, 2] || '1'
            next_page = page_number.to_i + 1
            next_link = next_page <= 20 ? %(<link rel="next" href="/news?page=#{next_page}">) : ''

            Html2rss::RequestService::Response.new(
              body: "<html><head>#{next_link}</head><body><article><h1>page#{page_number}</h1></article></body></html>",
              url: ctx.url,
              headers: { 'content-type' => 'text/html' }
            )
          end
        end

        it 'caps total pages at the system budget ceiling and logs the clamp', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
          allow(Html2rss::Log).to receive(:warn)

          expect(feed.items.map(&:title)).to eq(
            %w[page1 page2 page3 page4 page5 page6 page7 page8 page9 page10]
          )
          expect(Html2rss::RequestService).to have_received(:execute).exactly(
            Html2rss::RequestService::Policy::MAX_REQUESTS_CEILING
          ).times
          expect(Html2rss::Log).to have_received(:warn).with(
            /Html2rss::RequestSession: pagination max_pages=20 exceeds system ceiling=10; clamping to 10/
          )
        end
      end
    end

    context 'with config without title selector' do
      subject(:feed) do
        VCR.use_cassette(name) do
          config = described_class.config_from_yaml_file(config_file, name)
          described_class.feed(config)
        end
      end

      let(:name) { 'notitle' }

      it 'returns a RSS:Rss instance' do
        expect(feed).to be_a(RSS::Rss)
      end

      context 'with item' do
        let(:guid) { feed.items.first.guid.content }

        it 'autogenerates a guid', :aggregate_failures do
          expect(guid).to be_a(String)
          expect(guid).not_to be_empty
        end
      end
    end
  end

  describe '.json_feed' do
    context 'with config being a Hash' do
      let(:config) do
        described_class.config_from_yaml_file(config_file, name)
      end
      let(:feed_return) { VCR.use_cassette(name) { described_class.json_feed(config) } }
      let(:first_item) { feed_return[:items].first }

      it 'returns the channel metadata' do
        expect(feed_return).to include(
          version: 'https://jsonfeed.org/version/1.1',
          title: 'Releases · nuxt/nuxt.js · GitHub',
          home_page_url: 'https://github.com/nuxt/nuxt.js/releases'
        )
      end

      it 'returns items' do
        expect(feed_return[:items]).not_to be_empty
      end

      it 'serializes the first item' do
        expect(first_item).to include(
          title: 'v2.10.2 (pi)',
          url: 'https://github.com/nuxt/nuxt.js/releases/tag/v2.10.2'
        )
      end
    end
  end

  describe '.auto_source' do
    let(:url) { 'https://www.welt.de/' }
    let(:feed_return) { VCR.use_cassette('welt') { described_class.auto_source(url) } }

    it 'returns a RSS::Rss instance with channel and items', :aggregate_failures, :slow do
      expect(feed_return).to be_a(RSS::Rss)
      expect(feed_return.channel.title).to eq 'WELT - Aktuelle Nachrichten, News, Hintergründe & Videos'
      expect(feed_return.channel.link).to eq 'https://www.welt.de/'
      expect(feed_return.items.size >= 29).to be true
    end

    context 'with items_selector' do
      before do
        allow(described_class).to receive(:feed).and_return(nil)
      end

      let(:items_selector) { '.css.selector' }

      it 'adds selectors.items selector and enhance to config' do
        described_class.auto_source(url, items_selector:)
        expect(described_class).to have_received(:feed).with(
          hash_including(selectors: { items: { selector: items_selector, enhance: true } })
        )
      end
    end

    context 'with max_redirects' do
      before do
        allow(described_class).to receive(:feed).and_return(nil)
      end

      it 'adds max_redirects to the generated config' do
        described_class.auto_source(url, max_redirects: 8)

        expect(described_class).to have_received(:feed).with(hash_including(max_redirects: 8))
      end
    end

    context 'with max_requests' do
      before do
        allow(described_class).to receive(:feed).and_return(nil)
      end

      it 'adds max_requests to the generated config' do
        described_class.auto_source(url, max_requests: 8)

        expect(described_class).to have_received(:feed).with(hash_including(max_requests: 8))
      end
    end

    it 'leaves max_requests unset when omitted so request budget can be inferred' do
      allow(described_class).to receive(:feed).and_return(nil)

      described_class.auto_source(url)

      expect(described_class).to have_received(:feed).with(hash_excluding(:max_requests))
    end
  end

  describe '.auto_json_feed' do
    let(:url) { 'https://www.welt.de/' }
    let(:feed_return) { VCR.use_cassette('welt') { described_class.auto_json_feed(url) } }

    it 'returns the channel metadata', :aggregate_failures, :slow do
      expect(feed_return).to include(
        version: 'https://jsonfeed.org/version/1.1',
        title: 'WELT - Aktuelle Nachrichten, News, Hintergründe & Videos',
        home_page_url: 'https://www.welt.de/'
      )
    end

    it 'returns items', :slow do
      expect(feed_return[:items].size >= 29).to be true
    end

    context 'with items_selector' do
      before do
        allow(described_class).to receive(:json_feed).and_return(nil)
      end

      let(:items_selector) { '.css.selector' }

      it 'adds selectors.items selector and enhance to config' do
        described_class.auto_json_feed(url, items_selector:)
        expect(described_class).to have_received(:json_feed).with(
          hash_including(selectors: { items: { selector: items_selector, enhance: true } })
        )
      end
    end

    context 'with max_redirects' do
      before do
        allow(described_class).to receive(:json_feed).and_return(nil)
      end

      it 'adds max_redirects to the generated config' do
        described_class.auto_json_feed(url, max_redirects: 8)

        expect(described_class).to have_received(:json_feed).with(hash_including(max_redirects: 8))
      end
    end

    context 'with max_requests' do
      before do
        allow(described_class).to receive(:json_feed).and_return(nil)
      end

      it 'adds max_requests to the generated config' do
        described_class.auto_json_feed(url, max_requests: 8)

        expect(described_class).to have_received(:json_feed).with(hash_including(max_requests: 8))
      end
    end

    it 'leaves max_requests unset when omitted so request budget can be inferred' do
      allow(described_class).to receive(:json_feed).and_return(nil)

      described_class.auto_json_feed(url)

      expect(described_class).to have_received(:json_feed).with(hash_excluding(:max_requests))
    end
  end
end
