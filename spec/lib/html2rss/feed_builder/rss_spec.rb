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
    end.to raise_error(ArgumentError, 'generator must be a non-blank String')
  end

  it 'rejects a non-string generator' do
    expect do
      described_class.new(channel:, articles:, generator: 1)
    end.to raise_error(ArgumentError, 'generator must be a non-blank String')
  end

  it 'rejects a generator that is blank only after stripping both sides' do
    expect do
      described_class.new(channel:, articles:, generator: " \n")
    end.to raise_error(ArgumentError, 'generator must be a non-blank String')
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
          'managingEditor' => 'Channel Author',
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
                        ttl: nil,
                        last_build_date: nil)
      end

      it 'renders the link, image and author as strings', :aggregate_failures do
        expect(channel_tag.xpath('link').text).to eq('http://example.com/')
        expect(channel_tag.css('image > url').text).to eq('http://example.com/image.jpg')
        expect(channel_tag.xpath('managingEditor').text).to eq('Channel Author')
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
