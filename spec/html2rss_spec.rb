RSpec.describe Html2rss do
  let(:config) { Html2rss::Config.new(yaml_config, name) }
  let(:name) { 'nuxt-releases' }
  let(:config_file) { File.join(['spec', 'config.test.yml']) }
  let(:yaml_config) { YAML.safe_load(File.open(config_file)) }

  it 'has a version number' do
    expect(Html2rss::VERSION).not_to be nil
  end

  describe '.feed_from_yaml_config' do
    subject(:feed) do
      VCR.use_cassette('nuxt-releases') do
        described_class.feed_from_yaml_config(config_file, name)
      end
    end

    it 'returns a RSS:Rss instance' do
      expect(feed).to be_a_kind_of(RSS::Rss)
    end
  end

  describe '.feed' do
    subject(:xml) { Nokogiri::XML(feed_return.to_s) }

    let(:feed_return) { VCR.use_cassette('nuxt-releases') { described_class.feed(config) } }

    it 'returns a RSS::Rss instance' do
      expect(feed_return).to be_a_kind_of(RSS::Rss)
    end

    it 'sets the request headers' do
      expect(Faraday).to receive(:new)
        .with(hash_including(headers: yaml_config['headers']))
        .and_call_original

      VCR.use_cassette('nuxt-releases') { described_class.feed(config) }
    end

    describe 'feed.channel' do
      it 'sets a title' do
        expect(xml.css('channel > title').text).to eq 'Nuxt.js Github Releases'
      end

      it 'sets the link' do
        expect(xml.css('channel > link').text).to be_a(String)
      end

      it 'sets a URI::HTTP parsable link' do
        expect(
          URI(xml.css('channel > link').text)
        ).to be_a(URI::HTTP)
      end

      it 'sets a description' do
        expect(xml.css('channel > description').text).to eq 'An example config.'
      end

      it 'sets a ttl' do
        expect(xml.css('channel > ttl').text.to_i).to be > 0
      end

      it 'sets a generator' do
        expect(xml.css('channel > generator').text).to start_with('html2rss')
      end

      it 'has items' do
        expect(xml.css('channel > item').count).to be > 0
      end
    end

    describe 'feed.items' do
      subject(:item) { xml.css('channel > item').first }

      it 'formats item.title' do
        expect(item.css('title').text).to eq 'v1.4.4 (Atinux)'
      end

      it 'has a link' do
        expect(item.css('link').text).to start_with('https')
      end

      it 'has an author' do
        expect(item.css('author').text).to eq 'Atinux'
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

      describe 'item.description' do
        let(:description) { item.css('description').text }

        it 'has a description' do
          expect(description).to be_a(String)
        end

        it 'adds rel="nofollow noopener noreferrer" to all anchor elements' do
          Nokogiri::HTML(description).css('a').each do |anchor|
            expect(anchor.attr('rel')).to eq 'nofollow noopener noreferrer'
          end
        end

        it 'changes target="_blank" on all anchor elements' do
          Nokogiri::HTML(description).css('a').each do |anchor|
            expect(anchor.attr('target')).to eq '_blank'
          end
        end
      end
    end

    describe 'item.guid' do
      it 'stays the same string for each run' do
        first_guid = VCR.use_cassette('nuxt-releases-second-run') do
          described_class.feed(config)
        end.items.first.guid.content

        expect(feed_return.items.first.guid.content)
          .to be == first_guid
      end
    end
  end
end
