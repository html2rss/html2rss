# frozen_string_literal: true

# Shared examples for basic RSS feed validation
# These examples provide common test patterns for RSS feed generation and validation

RSpec.shared_examples 'generates valid RSS feed' do
  it 'generates a valid RSS feed', :aggregate_failures do
    expect(feed).to be_a(RSS::Rss)
    expect(feed.channel.title).to be_a(String)
    expect(feed.channel.link).to be_a(String)
  end

  it 'extracts the correct number of items', :aggregate_failures do
    expect(feed.items).to be_an(Array)
    expect(feed.items.size).to be > 0
  end
end

RSpec.shared_examples 'extracts valid item content' do
  it 'extracts titles correctly', :aggregate_failures do
    titles = items.filter_map(&:title)
    expect(titles).to all(be_a(String))
    expect(titles).to all(satisfy { |title| !title.strip.empty? })
  end

  it 'extracts descriptions correctly', :aggregate_failures do
    descriptions = items.filter_map(&:description)
    expect(descriptions).to all(be_a(String))
    expect(descriptions).to all(satisfy { |desc| !desc.strip.empty? })
  end

  it 'extracts URLs correctly', :aggregate_failures do
    urls = items.filter_map(&:link)
    expect(urls).to all(be_a(String))
    expect(urls).to all(satisfy { |url| !url.strip.empty? })
  end
end

RSpec.shared_examples 'extracts valid published dates' do
  it 'extracts published dates correctly', :aggregate_failures do
    items_with_time = items.select(&:pubDate)
    expect(items_with_time.size).to be > 0

    items_with_time.each do |item|
      expect(item.pubDate).to be_a(Time)
    end
  end
end
