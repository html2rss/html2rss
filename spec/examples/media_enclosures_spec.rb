# frozen_string_literal: true

require 'spec_helper'
require 'time'

RSpec.describe 'Media Enclosures Configuration', type: :example do
  subject(:feed) { generate_feed_from_config(config, config_name, :html) }

  let(:config_name) { 'media_enclosures_site' }
  let(:config) { load_example_configuration(config_name) }
  let(:items) { feed.items }

  let(:expected_items) do
    [
      {
        title: 'Episode 42: The Future of AI in Web Development',
        link: 'https://example.com/episodes/episode-42-ai-web-dev',
        description_includes: [
          '<audio controls',
          'AI-assisted coding'
        ],
        categories: ['3240'],
        pub_date: 'Mon, 15 Jan 2024 10:00:00 +0000',
        enclosure: { url: 'https://example.com/episodes/episode-42-ai-web-dev.mp3', type: 'audio/mpeg', length: 0 }
      },
      {
        title: 'Episode 41: Building Scalable React Applications',
        link: 'https://example.com/episodes/episode-41-scalable-react',
        description_includes: [
          '<audio controls',
          'performance optimization'
        ],
        categories: ['2880'],
        pub_date: 'Mon, 08 Jan 2024 10:00:00 +0000',
        enclosure: { url: 'https://example.com/episodes/episode-41-scalable-react.mp3', type: 'audio/mpeg', length: 0 }
      },
      {
        title: 'Episode 40: Special - Interview with Tech Industry Leaders',
        link: 'https://example.com/episodes/episode-40-special-interview',
        description_includes: [
          '<audio controls',
          'tech industry leaders'
        ],
        categories: ['4500'],
        pub_date: 'Mon, 01 Jan 2024 10:00:00 +0000',
        enclosure: { url: 'https://example.com/episodes/episode-40-special-interview.mp3', type: 'audio/mpeg', length: 0 }
      },
      {
        title: 'Episode 39: Quick Tips for CSS Grid',
        link: 'https://example.com/episodes/episode-39-css-grid-tips',
        description_includes: [
          '<audio controls',
          'essential CSS Grid tips'
        ],
        categories: ['1800'],
        pub_date: 'Mon, 25 Dec 2023 10:00:00 +0000',
        enclosure: { url: 'https://example.com/episodes/episode-39-css-grid-tips.mp3', type: 'audio/mpeg', length: 0 }
      },
      {
        title: 'Episode 38: Live Coding Session - Building a Todo App',
        link: 'https://example.com/episodes/episode-38-live-coding',
        description_includes: [
          'live coding session',
          'Implementing core functionality'
        ],
        categories: ['5400'],
        pub_date: 'Mon, 18 Dec 2023 10:00:00 +0000',
        enclosure: nil
      },
      {
        title: 'Episode 37: Text-Only Episode - Reading List',
        link: 'https://example.com/episodes/episode-37-reading-list',
        description_includes: [
          'text-only episode',
          "This month's recommendations include books on software architecture"
        ],
        categories: ['0'],
        pub_date: 'Mon, 11 Dec 2023 10:00:00 +0000',
        enclosure: nil
      }
    ]
  end

  it 'translates every episode into an RSS item with markdown summaries' do
    expect_feed_items(items, expected_items)
  end

  it 'emits absolute URLs for episode pages and media assets' do
    urls = items.map(&:link)
    expect(urls).to all(start_with('https://example.com/episodes/'))
  end
end
