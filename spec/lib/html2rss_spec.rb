# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss do
  let(:config_file) { File.join(%w[spec fixtures feeds.test.yml]) }
  let(:name) { 'nuxt-releases' }

  it 'has a version number' do
    expect(Html2rss::VERSION).not_to be_nil
  end

  it 'defines a Error class' do
    expect(Html2rss::Error).to be < StandardError
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
        expect(Faraday).to have_received(:new).with(hash_including(headers: config[:headers]))
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
  end
end
