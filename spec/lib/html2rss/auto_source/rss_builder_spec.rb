# frozen_string_literal: true

RSpec.describe Html2rss::RssBuilder do
  subject(:instance) do
    described_class.new(channel:,
                        articles:,
                        stylesheets: [
                          Html2rss::RssBuilder::Stylesheet.new(href: 'rss.xsl', type: 'text/xsl')
                        ])
  end

  let(:articles) do
    [
      Html2rss::AutoSource::Article.new(url: 'http://example.com/1',
                                        id: 1,
                                        title: 'Title 1',
                                        description: 'Description 1',
                                        published_at: '1969-12-31 23:59:59',
                                        image: 'http://example.com/image1.jpg',
                                        scraper: RSpec),
      Html2rss::AutoSource::Article.new(url: 'http://example.com/2',
                                        id: 2,
                                        title: 'Title 2',
                                        description: 'Description 2',
                                        published_at: '1969-12-31 23:59:59',
                                        image: 'http://example.com/image2.jpg',
                                        scraper: RSpec)
    ]
  end
  let(:channel) do
    instance_double(Html2rss::AutoSource::Channel,
                    title: 'Test Channel',
                    url: 'http://example.com',
                    description: 'A test channel',
                    language: 'en',
                    image: 'http://example.com/image.jpg',
                    ttl: 12,
                    last_build_date: 'Tue, 01 Jan 2019 00:00:00 GMT')
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
          'generator' => "html2rss V. #{Html2rss::VERSION} (scrapers: [RSpec=2])"
        }
      end

      it 'has the correct attributes', :aggregate_failures do
        tags.each do |tag, matcher|
          expect(channel_tag.css(tag).text).to match(matcher), tag
        end
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

      it 'has tags with correct values', :aggregate_failures do
        %i[title description guid].each do |tag|
          expect(item.css(tag).text).to eq(article.public_send(tag).to_s), tag
        end

        expect(item.css('link').text).to eq(article.url.to_s), 'link'
        expect(item.css('pubDate').text).to eq(article.published_at.rfc822), 'pubDate'
      end

      it 'has an enclosure tag with the correct attributes' do
        enclosure = item.css('enclosure').first

        expect(enclosure[:url]).to match(article.image.to_s)
      end
    end
  end
end
