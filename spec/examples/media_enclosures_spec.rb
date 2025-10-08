# frozen_string_literal: true

require 'spec_helper'
require 'time'

RSpec.describe 'Media Enclosures Configuration', type: :example do
  subject(:feed) { generate_feed_from_config(config, config_name, :html) }

  let(:config_name) { 'media_enclosures_site' }
  let(:config) { load_example_configuration(config_name) }
  let(:items) { feed.items }
  let(:expected_titles) do
    [
      'Episode 42: The Future of AI in Web Development',
      'Episode 41: Building Scalable React Applications',
      'Episode 40: Special - Interview with Tech Industry Leaders',
      'Episode 39: Quick Tips for CSS Grid',
      'Episode 38: Live Coding Session - Building a Todo App',
      'Episode 37: Text-Only Episode - Reading List'
    ]
  end

  let(:expected_links) do
    [
      'https://example.com/episodes/episode-42-ai-web-dev',
      'https://example.com/episodes/episode-41-scalable-react',
      'https://example.com/episodes/episode-40-special-interview',
      'https://example.com/episodes/episode-39-css-grid-tips',
      'https://example.com/episodes/episode-38-live-coding',
      'https://example.com/episodes/episode-37-reading-list'
    ]
  end

  let(:expected_descriptions) do
    [
      <<~HTML.chomp,
        <audio controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous">
                    <source src="https://example.com/episodes/episode-42-ai-web-dev.mp3" type="audio/mpeg">
                  </audio>

        In this episode, we explore how artificial intelligence is revolutionizing web development. We discuss the latest tools, frameworks, and methodologies that are changing the way developers build applications. Our guest speaker, Dr. Sarah Johnson, shares insights from her research on AI-assisted coding and the potential impact on the industry. Introduction to AI in web development Current tools and frameworks Future predictions and trends

        <details>
          <summary>Available resources</summary>
          <table>
          <thead>
            <tr>
              <th>Type</th>
              <th>URL</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr>
          <td>🎵 Audio</td>
          <td><a href="https://example.com/episodes/episode-42-ai-web-dev.mp3" target="_blank" rel="nofollow noopener noreferrer">https://example.com/episodes/episode-42-ai-web-dev.mp3</a></td>
          <td><a href="https://example.com/episodes/episode-42-ai-web-dev.mp3" target="_blank" rel="nofollow noopener noreferrer">Play</a> |
        <a href="https://example.com/episodes/episode-42-ai-web-dev.mp3" target="_blank" rel="nofollow noopener noreferrer" download="">Download</a></td>
        </tr>
          </tbody>
        </table>
        </details>
      HTML
      <<~HTML.chomp,
        <audio controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous">
                    <source src="https://example.com/episodes/episode-41-scalable-react.mp3" type="audio/mpeg">
                  </audio>

        This episode covers best practices for building scalable React applications. We dive deep into performance optimization, state management, and architectural patterns. Topics include: Component optimization techniques State management strategies Code splitting and lazy loading Testing strategies for large applications

        <details>
          <summary>Available resources</summary>
          <table>
          <thead>
            <tr>
              <th>Type</th>
              <th>URL</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr>
          <td>🎵 Audio</td>
          <td><a href="https://example.com/episodes/episode-41-scalable-react.mp3" target="_blank" rel="nofollow noopener noreferrer">https://example.com/episodes/episode-41-scalable-react.mp3</a></td>
          <td><a href="https://example.com/episodes/episode-41-scalable-react.mp3" target="_blank" rel="nofollow noopener noreferrer">Play</a> |
        <a href="https://example.com/episodes/episode-41-scalable-react.mp3" target="_blank" rel="nofollow noopener noreferrer" download="">Download</a></td>
        </tr>
          </tbody>
        </table>
        </details>
      HTML
      <<~HTML.chomp,
        <audio controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous">
                    <source src="https://example.com/episodes/episode-40-special-interview.mp3" type="audio/mpeg">
                  </audio>

        In this special episode, we interview three tech industry leaders about the current state of technology and where they see the industry heading in the next five years. Our guests include: John Smith, CTO of TechCorp Maria Garcia, VP of Engineering at StartupXYZ David Chen, Principal Architect at BigTech Inc This is a longer episode with in-depth discussions about technology trends, career advice, and industry insights.

        <details>
          <summary>Available resources</summary>
          <table>
          <thead>
            <tr>
              <th>Type</th>
              <th>URL</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr>
          <td>🎵 Audio</td>
          <td><a href="https://example.com/episodes/episode-40-special-interview.mp3" target="_blank" rel="nofollow noopener noreferrer">https://example.com/episodes/episode-40-special-interview.mp3</a></td>
          <td><a href="https://example.com/episodes/episode-40-special-interview.mp3" target="_blank" rel="nofollow noopener noreferrer">Play</a> |
        <a href="https://example.com/episodes/episode-40-special-interview.mp3" target="_blank" rel="nofollow noopener noreferrer" download="">Download</a></td>
        </tr>
          </tbody>
        </table>
        </details>
      HTML
      <<~HTML.chomp,
        <audio controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous">
                    <source src="https://example.com/episodes/episode-39-css-grid-tips.mp3" type="audio/mpeg">
                  </audio>

        A quick episode covering essential CSS Grid tips and tricks. Perfect for developers who want to improve their layout skills. We cover: Basic grid concepts Common use cases Browser support considerations

        <details>
          <summary>Available resources</summary>
          <table>
          <thead>
            <tr>
              <th>Type</th>
              <th>URL</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            <tr>
          <td>🎵 Audio</td>
          <td><a href="https://example.com/episodes/episode-39-css-grid-tips.mp3" target="_blank" rel="nofollow noopener noreferrer">https://example.com/episodes/episode-39-css-grid-tips.mp3</a></td>
          <td><a href="https://example.com/episodes/episode-39-css-grid-tips.mp3" target="_blank" rel="nofollow noopener noreferrer">Play</a> |
        <a href="https://example.com/episodes/episode-39-css-grid-tips.mp3" target="_blank" rel="nofollow noopener noreferrer" download="">Download</a></td>
        </tr>
          </tbody>
        </table>
        </details>
      HTML
      "In this episode, we do a live coding session building a todo application from scratch. Watch as we implement features step by step. This episode includes: Project setup and planning Implementing core functionality Adding advanced features Testing and deployment",
      "This is a text-only episode featuring our monthly reading list. We share the best articles, books, and resources we've discovered. This month's recommendations include books on software architecture, design patterns, and career development."
    ]
  end

  let(:expected_categories) do
    [
      ['3240'],
      ['2880'],
      ['4500'],
      ['1800'],
      ['5400'],
      ['0']
    ]
  end

  let(:expected_pubdates) do
    [
      'Mon, 15 Jan 2024 10:00:00 +0000',
      'Mon, 08 Jan 2024 10:00:00 +0000',
      'Mon, 01 Jan 2024 10:00:00 +0000',
      'Mon, 25 Dec 2023 10:00:00 +0000',
      'Mon, 18 Dec 2023 10:00:00 +0000',
      'Mon, 11 Dec 2023 10:00:00 +0000'
    ]
  end

  let(:expected_enclosures) do
    [
      ['https://example.com/episodes/episode-42-ai-web-dev.mp3', 'audio/mpeg', 0],
      ['https://example.com/episodes/episode-41-scalable-react.mp3', 'audio/mpeg', 0],
      ['https://example.com/episodes/episode-40-special-interview.mp3', 'audio/mpeg', 0],
      ['https://example.com/episodes/episode-39-css-grid-tips.mp3', 'audio/mpeg', 0],
      [nil, nil, nil],
      [nil, nil, nil]
    ]
  end

  it 'translates every episode into an RSS item with markdown summaries', :aggregate_failures do
    expect(items.size).to eq(expected_titles.size)
    expect(items.map(&:title)).to eq(expected_titles)
    expect(items.map(&:description)).to eq(expected_descriptions)
    expect(items.map { |item| item.pubDate.rfc2822 }).to eq(expected_pubdates)
  end

  it 'emits absolute URLs for episode pages and media assets', :aggregate_failures do
    expect(items.map(&:link)).to eq(expected_links)
    expect(items.map do |item|
             enclosure = item.enclosure
             [enclosure&.url, enclosure&.type, enclosure&.length]
           end).to eq(expected_enclosures)
  end

  it 'records playback duration as a numeric category' do
    expect(items.map { |item| item.categories.map(&:content) })
      .to eq(expected_categories)
  end

  it 'leaves purely textual episodes without an enclosure' do
    video_episode = items.find { |item| item.title.include?('Live Coding Session') }
    trailing_episode = items.last

    expect(video_episode.enclosure).to be_nil
    expect(trailing_episode.title).to eq('Episode 37: Text-Only Episode - Reading List')
    expect(trailing_episode.enclosure).to be_nil
  end
end
