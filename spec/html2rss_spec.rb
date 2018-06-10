RSpec.describe Html2rss do
  it 'has a version number' do
    expect(Html2rss::VERSION).not_to be nil
  end

  let(:config_file) { File.join(['spec', 'config.test.yml']) }
  let(:name) { 'nuxt-releases' }
  let(:yaml_config) { YAML.load(File.open(config_file)) }
  let(:config) { Html2rss::Config.new(yaml_config, name) }

  describe '.feed_from_yaml_config' do
    subject do
      VCR.use_cassette('nuxt-releases') do
        Html2rss.feed_from_yaml_config(config_file, name)
      end
    end

    it 'returns a RSS:Rss instance' do
      expect(subject).to be_a_kind_of(RSS::Rss)
    end
  end

  describe '.feed' do
    let(:feed_return) { VCR.use_cassette('nuxt-releases') { Html2rss.feed(config) } }
    let(:xml) { Nokogiri::XML(feed_return.to_s) }

    subject { xml }

    it 'returns a RSS::Rss instance' do
      expect(feed_return).to be_a_kind_of(RSS::Rss)
    end

    it 'sets the request headers' do
      expect(Faraday).to receive(:new)
        .with(hash_including(headers: yaml_config['headers']))
        .and_call_original

      VCR.use_cassette('nuxt-releases') { Html2rss.feed(config) }
    end

    context 'rss channel' do
      it 'sets a title' do
        expect(subject.css('channel > title').text).to be_a(String)
      end

      it 'sets the link' do
        expect(subject.css('channel > link').text).to be_a(String)
      end

      it 'sets a URI::HTTP parsable link' do
        expect(
          URI(subject.css('channel > link').text)
        ).to be_a(URI::HTTP)
      end

      it 'sets a description' do
        expect(subject.css('channel > description').text).to be_a(String)
      end

      it 'sets a ttl' do
        expect(subject.css('channel > ttl').text.to_i).to be > 0
      end

      it 'sets a generator' do
        expect(subject.css('channel > generator').text).to be_a(String)
      end

      it 'has items' do
        expect(subject.css('channel > item').count).to be > 0
      end
    end

    context 'rss items' do
      subject { xml.css('channel > item').first }

      context 'title' do
        it 'is a String' do
          expect(subject.css('title').text).to be_a(String)
        end

        it 'is formatted' do
          expect(subject.css('title').text).to eq 'v1.4.0 (@Atinux)'
        end
      end

      it 'has a link' do
        expect(subject.css('link').text).to be_a(String)
      end

      it 'has an author' do
        expect(subject.css('author').text).to be_a(String)
      end

      it 'has a pubDate' do
        expect(subject.css('pubDate').text).to be_a(String)
      end

      it 'has a guid' do
        expect(subject.css('guid').text).to be_a(String)
      end

      context 'description' do
        let(:description) { subject.css('description').text }
        it 'has a description' do
          expect(description).to be_a(String)
        end

        it 'adds rel="nofollow noopener noreferrer" to all anchor elements' do
          Nokogiri::HTML(description).css('a').each do |anchor|
            expect(anchor.attr('rel')).to eq 'nofollow noopener noreferrer'
          end
        end
      end
    end

    context "item's guid" do
      it 'stays the same string for each run' do
        first_guid = VCR.use_cassette('nuxt-releases-second-run') do
          Html2rss.feed(config)
        end.items.first.guid.content

        expect(feed_return.items.first.guid.content)
          .to be == first_guid
      end
    end
  end
end
