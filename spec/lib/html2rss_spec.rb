# frozen_string_literal: true

RSpec.describe Html2rss do
  let(:config_file) { File.join(%w[spec fixtures feeds.test.yml]) }
  let(:name) { 'nuxt-releases' }

  it 'has a version number' do
    expect(Html2rss::VERSION).not_to be_nil
  end

  it 'defines a Error class' do
    expect(Html2rss::Error).to be < StandardError
  end

  describe '::CONFIG_KEY_FEEDS' do
    it { expect(described_class::CONFIG_KEY_FEEDS).to eq :feeds }
  end

  describe '.config_from_yaml_config' do
    context 'with html response' do
      subject(:feed) do
        VCR.use_cassette(name) { described_class.config_from_yaml_config(config_file, name) }
      end

      it { expect(feed).to be_a(Hash) }
    end

    xcontext 'with json response' do
      subject(:feed) do
        VCR.use_cassette(name) { described_class.config_from_yaml_config(config_file, name) }
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

    context 'with config without title selector' do
      subject(:feed) do
        VCR.use_cassette(name) { described_class.feed_from_yaml_config(config_file, name) }
      end

      let(:name) { 'notitle' }

      it 'returns a RSS:Rss instance' do
        expect(feed).to be_a(RSS::Rss)
      end

      context 'with item' do
        subject(:item) { Nokogiri.XML(feed.to_s).css('item:first') }

        let(:guid) { item.css('guid').text }

        it 'autogenerates a guid', :aggregate_failures do
          expect(guid).to be_a String
          expect(guid.bytesize).to eq 40
        end
      end
    end
  end

  describe '.feed' do
    context 'with config being a Config' do
      subject(:xml) { Nokogiri.XML(feed_return.to_s) }

      let(:yaml_config) { YAML.safe_load(File.open(config_file), symbolize_names: true) }
      let(:config) do
        feed_config = yaml_config[described_class::CONFIG_KEY_FEEDS][name.to_sym]
        global_config = yaml_config.reject { |k| k == described_class::CONFIG_KEY_FEEDS }
        Html2rss::Config.new(feed_config, global_config)
      end
      let(:feed_return) { VCR.use_cassette(name) { described_class.feed(config) } }

      before do
        allow(Faraday).to receive(:new).with(hash_including(headers: yaml_config[:headers])).and_call_original
      end

      it 'returns a RSS::Rss instance' do
        expect(feed_return).to be_a(RSS::Rss)
      end

      it 'sets the request headers' do
        VCR.use_cassette(name) { described_class.feed(config) }

        expect(Faraday).to have_received(:new).with(hash_including(headers: yaml_config[:headers]))
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
          it 'has a pubDate' do
            expect(item.css('pubDate').text).not_to eq ''
          end

          it 'is in rfc822 format' do
            pub_date = item.css('pubDate').text
            expect(Time.parse(pub_date).rfc822.to_s).to eq pub_date
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
          yaml_config[described_class::CONFIG_KEY_FEEDS][name.to_sym][:selectors][:items][:order] = 'reverse'
        end

        it 'reverses the item ordering' do
          expect(xml.css('channel > item').last.css('title').text).to eq 'v2.10.2 (pi)'
        end
      end
    end

    context 'with config having channel headers and json: true' do
      subject(:categories) do
        VCR.use_cassette('httpbin-headers') do
          described_class.feed(feed_config)
        end.items.first.categories.map(&:content)
      end

      let(:feed_config) do
        {
          channel: {
            url: 'https://httpbin.org/headers',
            title: 'httpbin headers',
            json: true,
            headers: {
              'User-Agent': 'html2rss-request',
              'X-Something': 'Foobar',
              Authorization: 'Token deadbea7',
              Cookie: 'monster=MeWantCookie'
            }
          },
          selectors: {
            items: { selector: 'object' },
            title: { selector: 'host' },
            something: { selector: 'x-something' },
            authorization: { selector: 'authorization' },
            cookie: { selector: 'cookie' },
            categories: %i[title something authorization cookie]
          }
        }
      end

      it 'has the headers' do
        expect(categories).to include('httpbin.org', 'Foobar', 'Token deadbea7', 'monster=MeWantCookie')
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
  end
end
