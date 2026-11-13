# frozen_string_literal: true

RSpec.describe Html2rss::FeedBuilder::Rss do
  subject(:instance) do
    described_class.new(channel:,
                        articles:,
                        stylesheets: [
                          { href: 'rss.xsl', type: 'text/xsl' }
                        ],
                        generator: "html2rss V. #{Html2rss::VERSION} (scrapers: RSpec (1), AutoSource::Html (1))")
  end

  let(:channel) do
    instance_double(Html2rss::Channel,
                    title: 'Test Channel',
                    url: 'http://example.com',
                    description: 'A test channel',
                    language: 'en',
                    image: 'http://example.com/image.jpg',
                    author: 'Channel Author',
                    categories: [],
                    explicit: nil,
                    ttl: 12,
                    last_build_date: 'Tue, 01 Jan 2019 00:00:00 GMT')
  end
  let(:articles) do
    [
      Html2rss::Article.new(url: 'http://example.com/1',
                            id: 1,
                            title: 'Title 1',
                            description: 'Description 1',
                            published_at: '1969-12-31 23:59:59',
                            image: 'http://example.com/image1.jpg',
                            scraper: RSpec),
      Html2rss::Article.new(url: 'http://example.com/2',
                            id: 2,
                            title: 'Title 2',
                            description: 'Description 2',
                            published_at: '1969-12-31 23:59:59',
                            image: 'http://example.com/image2.jpg',
                            scraper: Html2rss::AutoSource::Scraper::Html)
    ]
  end

  it { expect(described_class).to be_a Class }

  it 'requires a non-blank generator' do
    expect do
      described_class.new(channel:, articles:, generator: ' ')
    end.to raise_error(Html2rss::InvalidOption, 'generator must be a non-blank String')
  end

  it 'rejects a non-string generator' do
    expect do
      described_class.new(channel:, articles:, generator: 1)
    end.to raise_error(Html2rss::InvalidOption, 'generator must be a non-blank String')
  end

  it 'rejects a generator that is blank only after stripping both sides' do
    expect do
      described_class.new(channel:, articles:, generator: " \n")
    end.to raise_error(Html2rss::InvalidOption, 'generator must be a non-blank String')
  end

  it 'accepts a String subclass generator' do
    generator = Class.new(String).new('html2rss')
    expect(described_class.new(channel:, articles:, generator:).call).to be_a(RSS::Rss)
  end

  it 'builds without stylesheets when none are given' do
    rss = described_class.new(channel:, articles:, generator: 'html2rss').call
    expect(rss.to_s).not_to include('xml-stylesheet')
  end

  describe '#call' do
    subject(:rss) { instance.call }

    let(:rss_feed) do
      <<~RSS.strip
        <?xml version="1.0" encoding="UTF-8"?>
        <?xml-stylesheet href="rss.xsl" type="text/xsl" media="all"?>
        <rss version="2.0"\n
      RSS
    end

    it 'returns an RSS 2.0 Rss object', :aggregate_failures do
      expect(rss).to be_a(RSS::Rss)
      expect(rss.to_s).to start_with(rss_feed)
    end

    context 'with <channel> tag' do
      subject(:channel_tag) { Nokogiri::XML(rss.to_s).css('channel').first }

      let(:tags) do
        {
          'language' => 'en',
          'title' => 'Test Channel',
          'link' => 'http://example.com',
          'description' => 'A test channel',
          'generator' => "html2rss V. #{Html2rss::VERSION} (scrapers: RSpec (1), AutoSource::Html (1))"
        }
      end

      it 'has the correct attributes', :aggregate_failures do
        tags.each do |tag, matcher|
          expect(channel_tag.xpath(tag).text).to match(matcher), tag
        end
        expect(channel_tag.css('image > url').text).to eq('http://example.com/image.jpg')
        expect(channel_tag.css('image > title').text).to eq('Test Channel')
      end

      it 'carries the ttl and last build date', :aggregate_failures do
        expect(channel_tag.css('ttl').text).to eq('12')
        expect(channel_tag.xpath('pubDate').text).to eq('Tue, 01 Jan 2019 00:00:00 +0000')
      end
    end

    context 'when the channel url and image are Html2rss::Url objects' do
      subject(:channel_tag) { Nokogiri::XML(rss.to_s).css('channel').first }

      let(:channel) do
        instance_double(Html2rss::Channel,
                        title: 'Test Channel',
                        url: Html2rss::Url.from_absolute('http://example.com/'),
                        description: 'A test channel',
                        language: 'en',
                        image: Html2rss::Url.from_absolute('http://example.com/image.jpg'),
                        author: 'Channel Author',
                        categories: [],
                        explicit: nil,
                        ttl: nil,
                        last_build_date: nil)
      end

      it 'renders the link and image as strings', :aggregate_failures do
        expect(channel_tag.xpath('link').text).to eq('http://example.com/')
        expect(channel_tag.css('image > url').text).to eq('http://example.com/image.jpg')
      end
    end

    context 'with a channel author' do
      subject(:managing_editors) do
        ['Channel Author', 'editor@example.com', 'editor@example.com (Channel Author)', 'editor@example.com Author']
          .map do |author|
            authored = instance_double(Html2rss::Channel, title: 'T', url: 'http://example.com', description: 'D',
                                                          language: 'en', image: nil, author:, ttl: nil,
                                                          last_build_date: nil)
            channel_tag = Nokogiri::XML(described_class.new(channel: authored, articles: [], generator: 'g').call.to_s)
            channel_tag.at_xpath('//channel/managingEditor')&.text
          end
      end

      it 'carries it as managingEditor only in the RSS 2.0 email form' do
        expect(managing_editors).to eq([nil, 'editor@example.com', 'editor@example.com (Channel Author)', nil])
      end
    end

    context 'when the channel has no image, author or ttl' do
      subject(:bare_channel_tag) { Nokogiri::XML(bare_rss.to_s).css('channel').first }

      let(:bare_channel) do
        instance_double(Html2rss::Channel, title: 'Bare', url: 'http://example.com', description: 'D',
                                           language: 'en', image: nil, author: nil, ttl: nil, last_build_date: nil)
      end
      let(:bare_rss) do
        described_class.new(channel: bare_channel, articles: [], generator: 'html2rss').call
      end

      it 'omits the optional channel elements', :aggregate_failures do
        expect(bare_channel_tag.css('image')).to be_empty
        expect(bare_channel_tag.css('managingEditor')).to be_empty
        expect(bare_channel_tag.css('author')).to be_empty
      end
    end

    context 'with the <item> tags' do
      let(:items) { Nokogiri::XML(rss.to_s).css('item') }

      it 'has the correct number of items' do
        expect(items.size).to eq(articles.size)
      end
    end

    context 'with one <item> tags' do
      let(:item) { Nokogiri::XML(rss.to_s).css('item').first }
      let(:article) { articles.first }

      # rubocop:disable-next RSpec/ExampleLength -- title/guid/description/link/pubDate contract
      it 'has tags with correct values', :aggregate_failures do
        expect(item.css('title').text).to eq(article.title.to_s)
        expect(item.css('guid').text).to eq(article.guid.to_s)
        expect(item.css('description').text).to eq(
          Html2rss::FeedBuilder::ItemPresentation.description_for(article).to_s
        )
        expect(item.css('link').text).to eq(article.url.to_s), 'link'
        expect(item.css('pubDate').text).to eq(article.published_at.rfc822), 'pubDate'
      end

      it 'omits <enclosure> when the article only has an image' do
        expect(item.css('enclosure')).to be_empty
      end
    end

    context 'with an article that has an author, categories and no url' do
      let(:articles) do
        [
          Html2rss::Article.new(
            id: 1,
            title: 'Title 1',
            author: 'Jane Doe',
            categories: [' news ', 'tech', ''],
            description: 'Description 1',
            scraper: RSpec
          )
        ]
      end
      let(:item) { Nokogiri::XML(rss.to_s).css('item').first }

      it 'emits author, trimmed categories, an isPermaLink="false" guid and no link', :aggregate_failures do
        expect(item.at_css('author').text).to eq('Jane Doe')
        expect(item.css('category').map(&:text)).to eq(%w[news tech])
        expect(item.at_css('guid')['isPermaLink']).to eq('false')
        expect(item.at_css('link')).to be_nil
      end
    end

    context 'with a non-image enclosure' do
      let(:articles) do
        [
          Html2rss::Article.new(
            url: 'http://example.com/1',
            id: 1,
            title: 'Title 1',
            description: 'Description 1',
            published_at: '1969-12-31 23:59:59',
            image: 'http://example.com/image1.jpg',
            enclosures: [{
              url: Html2rss::Url.from_absolute('http://example.com/episode.mp3'),
              type: 'audio/mpeg',
              bytes_length: 0
            }],
            scraper: RSpec
          )
        ]
      end
      let(:item) { Nokogiri::XML(rss.to_s).css('item').first }

      it 'emits <enclosure> for the audio attachment and keeps image off enclosure', :aggregate_failures do
        enclosure = item.css('enclosure').first

        expect(enclosure[:url]).to eq('http://example.com/episode.mp3')
        expect(enclosure[:type]).to eq('audio/mpeg')
        expect(enclosure[:url]).not_to include('image1.jpg')
      end
    end

    context 'with a media feed' do
      subject(:items) { Nokogiri::XML(rss.to_s).css('item') }

      # Rows: [enclosure duration, item image]; the last item carries no enclosure.
      let(:articles) do
        [[3723, 'https://example.com/one.jpg'], [59], [7200], [3540], [359_999], [360_000], [360_001], [nil], nil]
          .each_with_index.map do |row, id|
          enclosures = row && [{ url: Html2rss::Url.from_absolute("https://example.com/#{id}.mp3"),
                                 type: 'audio/mpeg', bytes_length: 1200, duration: row[0] }]
          Html2rss::Article.new(url: "https://example.com/#{id}", id:, title: "Episode #{id}", image: row&.[](1),
                                enclosures:, scraper: RSpec)
        end
      end

      it 'adds the channel itunes image and author', :aggregate_failures do
        channel_tag = Nokogiri::XML(rss.to_s).at_css('channel')

        expect(channel_tag.at_xpath('itunes:image')['href']).to eq('http://example.com/image.jpg')
        expect(channel_tag.at_xpath('itunes:author').text).to eq('Channel Author')
      end

      it 'omits itunes explicit and category when the channel states neither' do
        expect(Nokogiri::XML(rss.to_s).xpath('//itunes:explicit | //itunes:category')).to be_empty
      end

      it 'formats each known enclosure duration as HH:MM:SS, as seconds from 100 hours on' do
        durations = items.map { |item| item.at_xpath('itunes:duration')&.text }

        expect(durations).to eq(
          ['01:02:03', '00:00:59', '02:00:00', '00:59:00', '99:59:59', '360000', '360001', nil, nil]
        )
      end

      it 'adds the item itunes image only when the item has an image' do
        images = items.map { |item| item.at_xpath('itunes:image')&.[]('href') }

        expect(images).to eq(['https://example.com/one.jpg'] + ([nil] * 8))
      end

      it 'emits the known byte length' do
        expect(items.first.at_css('enclosure')['length']).to eq('1200')
      end

      # rubocop:disable-next RSpec/ExampleLength -- the fields a podcast client reads, parsed back as one feed
      it 'parses with the rss library into the fields podcast clients play from', :aggregate_failures do
        parsed = RSS::Parser.parse(rss.to_s)
        episodes = parsed.items.select(&:enclosure)

        expect(rss.to_s).to include('xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"')
        expect(parsed.channel.itunes_author).to eq('Channel Author')
        expect(parsed.channel.itunes_image.href).to eq('http://example.com/image.jpg')
        expect(episodes.map { |item| item.enclosure.url }).to eq((0..7).map { |id| "https://example.com/#{id}.mp3" })
        expect(episodes.map { |item| [item.enclosure.type, item.enclosure.length] }.uniq).to eq([['audio/mpeg', 1200]])
        expect(episodes.map { |item| item.itunes_duration&.content }).to eq(
          ['01:02:03', '00:00:59', '02:00:00', '00:59:00', '99:59:59', '360000', '360001', nil]
        )
      end
    end

    context 'with a media feed whose channel states categories and the explicit flag' do
      subject(:channel_tag) { Nokogiri::XML(rss.to_s).at_xpath('/rss/channel') }

      let(:stated) do
        lambda do |explicit|
          instance_double(Html2rss::Channel, title: 'Show', url: 'http://example.com', description: 'D',
                                             language: 'en', image: nil, author: 'Host', ttl: nil,
                                             last_build_date: nil, explicit:,
                                             categories: [['Society & Culture', 'Documentary'], ['News']])
        end
      end
      let(:channel) { stated.call(true) }
      let(:articles) do
        [Html2rss::Article.new(url: 'http://example.com/1', id: 1, title: 'Episode 1', scraper: RSpec,
                               enclosures: [{ url: Html2rss::Url.from_absolute('http://example.com/1.mp3') }])]
      end

      it 'nests each subcategory in its category', :aggregate_failures do
        categories = channel_tag.xpath('itunes:category')

        expect(categories.map { _1['text'] }).to eq(['Society & Culture', 'News'])
        expect(categories.map { |node| node.xpath('itunes:category').map { _1['text'] } })
          .to eq([['Documentary'], []])
      end

      it 'writes the explicit flag as true or false', :aggregate_failures do
        unflagged = described_class.new(channel: stated.call(false), articles:, generator: 'html2rss').call

        expect(channel_tag.xpath('itunes:explicit').map(&:text)).to eq(['true'])
        expect(Nokogiri::XML(unflagged.to_s).xpath('//channel/itunes:explicit').map(&:text)).to eq(['false'])
      end

      it 'parses back with the rss library', :aggregate_failures do
        parsed = RSS::Parser.parse(rss.to_s).channel

        expect(parsed.itunes_explicit?).to be(true)
        expect(parsed.itunes_categories.map { [_1.text, _1.itunes_category&.text] })
          .to eq([['Society & Culture', 'Documentary'], ['News', nil]])
      end
    end

    context 'with a media feed whose channel has no image or author' do
      let(:channel) do
        instance_double(Html2rss::Channel, title: 'Bare', url: 'http://example.com', description: 'D',
                                           language: 'en', image: nil, author: nil, ttl: nil, last_build_date: nil,
                                           categories: [], explicit: nil)
      end
      let(:articles) do
        [Html2rss::Article.new(url: 'http://example.com/1', id: 1, title: 'Episode 1', scraper: RSpec,
                               enclosures: [{ url: Html2rss::Url.from_absolute('http://example.com/1.mp3') }])]
      end

      it 'omits the channel itunes tags' do
        expect(Nokogiri::XML(rss.to_s).at_css('channel').xpath('itunes:image | itunes:author')).to be_empty
      end
    end

    context 'when exactly half of the items carry audio' do
      let(:articles) do
        [Html2rss::Article.new(url: 'http://example.com/1', id: 1, title: 'Episode 1', scraper: RSpec,
                               image: 'http://example.com/1.jpg',
                               enclosures: [{ url: Html2rss::Url.from_absolute('http://example.com/1.mp3'),
                                              duration: 60 }]),
         Html2rss::Article.new(url: 'http://example.com/2', id: 2, title: 'Episode 2', scraper: RSpec)]
      end
      let(:channel) do
        instance_double(Html2rss::Channel, title: 'Show', url: 'http://example.com', description: 'D',
                                           language: 'en', image: 'http://example.com/show.jpg', author: 'Host',
                                           ttl: nil, last_build_date: nil, explicit: false, categories: [['News']])
      end

      it 'emits no itunes tags, not even the categories and explicit flag the channel states' do
        expect(Nokogiri::XML(rss.to_s).xpath('//itunes:*')).to be_empty
      end
    end

    context 'with a non-media feed' do
      let(:item) { Nokogiri::XML(rss.to_s).css('item').first }
      let(:articles) do
        [Html2rss::Article.new(url: 'http://example.com/1', id: 1, title: 'Title 1', scraper: RSpec,
                               enclosures: [{ url: Html2rss::Url.from_absolute('http://example.com/notes.pdf'),
                                              type: 'application/pdf' }])]
      end

      it 'emits the file enclosure with length 0 and no itunes tags', :aggregate_failures do
        expect(item.at_css('enclosure')['length']).to eq('0')
        expect(item.at_css('enclosure')['type']).to eq('application/pdf')
        expect(Nokogiri::XML(rss.to_s).xpath('//itunes:*')).to be_empty
      end
    end

    context 'when article description contains a style tag' do
      let(:articles) do
        [
          Html2rss::Article.new(
            url: 'http://example.com/1',
            id: 1,
            title: 'Title 1',
            description: '<p>Paragraph</p><style>body { background: black; }</style>',
            scraper: RSpec
          )
        ]
      end
      let(:item) { Nokogiri::XML(rss.to_s).css('item').first }

      it 'strips style tags from item description' do
        expect(item.css('description').text).to eq('<p>Paragraph</p>')
      end
    end

    context 'when title and author are blank' do
      let(:articles) do
        [
          Html2rss::Article.new(
            url: 'http://example.com/1',
            id: 1,
            title: '  ',
            author: '',
            description: 'Description 1',
            scraper: RSpec
          )
        ]
      end
      let(:item) { Nokogiri::XML(rss.to_s).css('item').first }

      it 'omits those tags because Article already turns blanks into nil', :aggregate_failures do
        expect(item.at_css('title')).to be_nil
        expect(item.at_css('author')).to be_nil
        expect(item.at_css('description').text).not_to be_empty
      end
    end

    context 'when presented description is empty' do
      let(:articles) do
        [
          Html2rss::Article.new(
            url: 'http://example.com/1',
            id: 1,
            title: 'Title 1',
            scraper: RSpec
          )
        ]
      end
      let(:item) { Nokogiri::XML(rss.to_s).css('item').first }

      it 'omits the description tag' do
        expect(item.at_css('description')).to be_nil
      end
    end
  end
end
