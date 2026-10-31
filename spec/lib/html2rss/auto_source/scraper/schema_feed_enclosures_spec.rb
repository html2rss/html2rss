# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Schema do
  subject(:result) do
    Html2rss::FeedResult.new(channel:, articles: [Html2rss::Article.new(**attributes)], status:)
  end

  let(:channel) do
    Html2rss::Channel.new(title: 'E', url: Html2rss::Url.from_absolute('https://example.com'), description: 'E',
                          language: 'en', ttl: 60, last_build_date: Time.utc(2024, 1, 1), image: nil, author: nil)
  end
  let(:status) { Html2rss::Status.build(articles: [], dedup_dropped: 0) }
  let(:html) do
    json = { '@type': 'NewsArticle', headline: 'Clip', url: 'https://example.com/clip',
             video: { '@type': 'VideoObject', contentUrl: 'https://example.com/clip.mp4',
                      encodingFormat: 'video/mp4' } }.to_json
    "<script type=\"application/ld+json\">#{json}</script>"
  end
  let(:attributes) do
    described_class.new(Nokogiri::HTML(html), url: 'https://example.com').first.merge(scraper: described_class)
  end

  it 'renders a JSON-LD video in RSS and JSON Feed', :aggregate_failures do
    enclosure = result.to_rss.items.first.enclosure
    expect([enclosure.url, enclosure.type]).to eq(['https://example.com/clip.mp4', 'video/mp4'])
    expect(result.to_json_feed[:items].first[:attachments]).to include(a_hash_including(mime_type: 'video/mp4'))
  end
end
