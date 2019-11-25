RSpec.describe Html2rss do
  let(:config_file) { File.join(%w[spec config.test.yml]) }
  let(:config_json_file) { File.join(%w[spec config.json.test.yml]) }
  let(:yaml_config) { YAML.safe_load(File.open(config_file)).deep_symbolize_keys }
  let(:name) { 'nuxt-releases' }
  let(:feed_config) { yaml_config[:feeds][name.to_sym] }
  let(:global_config) { yaml_config.reject { |k| k == :feeds } }
  let(:config) { Html2rss::Config.new(feed_config, global_config) }

  it 'has a version number' do
    expect(Html2rss::VERSION).not_to be nil
  end

  describe '.feed_from_yaml_config' do
    context 'with html response' do
      subject(:feed) do
        VCR.use_cassette('nuxt-releases') { described_class.feed_from_yaml_config(config_file, name) }
      end

      it 'returns a RSS:Rss instance' do
        expect(feed).to be_a_kind_of(RSS::Rss)
      end
    end

    context 'with json response' do
      subject(:feed) do
        VCR.use_cassette('config.json') { described_class.feed_from_yaml_config(config_json_file, 'json') }
      end

      it 'returns a RSS:Rss instance' do
        expect(feed).to be_a_kind_of(RSS::Rss)
      end

      context 'with returned rss feed' do
        subject(:xml) { Nokogiri.XML(feed.to_s) }

        it 'has the description derived from markdown' do
          expect(
            xml.css('item > description').first.text
          ).to eq '<h1>DOCTOR SLEEP</h1> <p>MPAA rating: R</p>'
        end
      end
    end
  end

  describe '.feed' do
    subject(:xml) { Nokogiri.XML(feed_return.to_s) }

    let(:feed_return) { VCR.use_cassette('nuxt-releases') { described_class.feed(config) } }

    before do
      allow(Faraday).to receive(:new).with(hash_including(headers: yaml_config[:headers])).and_call_original
    end

    it 'returns a RSS::Rss instance' do
      expect(feed_return).to be_a_kind_of(RSS::Rss)
    end

    it 'sets the request headers' do
      VCR.use_cassette('nuxt-releases') { described_class.feed(config) }

      expect(Faraday).to have_received(:new).with(hash_including(headers: yaml_config[:headers]))
    end

    describe 'feed.channel' do
      it 'sets a title' do
        expect(xml.css('channel > title').text).to eq 'github.com: Nuxt Nuxt.Js Releases'
      end

      describe 'channel.link' do
        it 'sets it to the feed-configs channel url' do
          expect(xml.css('channel > link').text).to eq 'https://github.com/nuxt/nuxt.js/releases'
        end

        it 'is parse-able by URI::HTTP' do
          expect(URI(xml.css('channel > link').text)).to be_a(URI::HTTP)
        end
      end

      it 'sets a description' do
        expect(
          xml.css('channel > description').text
        ).to eq 'Latest items from https://github.com/nuxt/nuxt.js/releases.'
      end

      it 'sets a ttl' do
        expect(xml.css('channel > ttl').text.to_i).to be > 0
      end

      describe '.generator' do
        subject(:generator) { xml.css('channel > generator').text }

        it 'starts with html2rss' do
          expect(generator).to start_with('html2rss')
        end

        it 'includes the version number' do
          expect(generator).to end_with(Html2rss::VERSION)
        end
      end

      it 'has items' do
        expect(xml.css('channel > item').count).to be > 0
      end
    end

    describe 'feed.items' do
      subject(:item) { xml.css('channel > item').first }

      it 'formats item.title' do
        expect(item.css('title').text).to eq 'v2.10.2 (pi)'
      end

      it 'has a link' do
        expect(item.css('link').text).to eq 'https://github.com/nuxt/nuxt.js/releases/tag/v2.10.2'
      end

      it 'has an author' do
        expect(item.css('author').text).to eq 'pi'
      end

      it 'has a guid' do
        expect(item.css('guid').text).to be_a(String)
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
        let(:description) { item.css('description').text }

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
          feed = VCR.use_cassette('nuxt-releases-second-run') do
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
  end

  context 'with config having channel headers and json: true' do
    subject(:categories) do
      VCR.use_cassette('httpbin-headers') {
        described_class.feed(feed_config)
      }.items.first.categories.map(&:content)
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
            'Authorization': 'Token deadbea7',
            'Cookie': 'monster=MeWantCookie'
          }
        },
        selectors: {
          items: { selector: 'hash' },
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
