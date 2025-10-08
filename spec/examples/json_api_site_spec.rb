# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'time'

RSpec.describe 'JSON API Site Configuration' do
  subject(:feed) do
    mock_request_service_with_json_fixture('json_api_site', 'https://example.com/posts')
    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples json_api_site.yml]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }
  let(:channel_url) { config.dig(:channel, :url) }
  let(:time_zone) { config.dig(:channel, :time_zone) }
  let(:items) { feed.items }
  let(:expected_titles) do
    [
      "ACME Corp's Revolutionary AI Breakthrough Changes Everything",
      'Climate Change Summit Reaches Historic Agreement',
      'Space Exploration Mission Discovers New Planet',
      'Medical Breakthrough Offers Hope for Cancer Patients',
      'Renewable Energy Reaches New Milestone',
      'Cybersecurity Threats Reach All-Time High'
    ]
  end

  let(:expected_descriptions) do
    [
      <<~HTML.chomp,
        <img src="https://example.com/images/ai-breakthrough.jpg" alt="ACME Corp&#39;s Revolutionary AI Breakthrough Changes Everything" title="ACME Corp&#39;s Revolutionary AI Breakthrough Changes Everything" loading="lazy" referrerpolicy="no-referrer" decoding="async" crossorigin="anonymous">

        ACME Corp scientists have developed a new artificial intelligence system that can process natural language with unprecedented accuracy. This breakthrough promises to revolutionize how we interact with technology. It can finally understand 'it works on my machine' and translate it to 'it's broken in production'. The system uses advanced neural networks and machine learning algorithms to understand context and nuance in human communication. It also knows when you're lying about your commit messages.

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
          <td>🖼️ Image</td>
          <td><a href="https://example.com/images/ai-breakthrough.jpg" target="_blank" rel="nofollow noopener noreferrer">https://example.com/images/ai-breakthrough.jpg</a></td>
          <td><a href="https://example.com/images/ai-breakthrough.jpg" target="_blank" rel="nofollow noopener noreferrer">View</a> |
        <a href="https://example.com/images/ai-breakthrough.jpg" target="_blank" rel="nofollow noopener noreferrer" download="">Download</a></td>
        </tr>
          </tbody>
        </table>
        </details>
      HTML
      <<~HTML.chomp,
        <img src="https://example.com/images/climate-summit.jpg" alt="Climate Change Summit Reaches Historic Agreement" title="Climate Change Summit Reaches Historic Agreement" loading="lazy" referrerpolicy="no-referrer" decoding="async" crossorigin="anonymous">

        World leaders have reached a groundbreaking agreement on climate change mitigation strategies. The new accord includes ambitious targets for carbon reduction and renewable energy adoption. This historic agreement represents a turning point in global environmental policy and sets the stage for significant changes in how nations approach sustainability.

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
          <td>🖼️ Image</td>
          <td><a href="https://example.com/images/climate-summit.jpg" target="_blank" rel="nofollow noopener noreferrer">https://example.com/images/climate-summit.jpg</a></td>
          <td><a href="https://example.com/images/climate-summit.jpg" target="_blank" rel="nofollow noopener noreferrer">View</a> |
        <a href="https://example.com/images/climate-summit.jpg" target="_blank" rel="nofollow noopener noreferrer" download="">Download</a></td>
        </tr>
          </tbody>
        </table>
        </details>
      HTML
      <<~HTML.chomp,
        <img src="https://example.com/images/space-discovery.jpg" alt="Space Exploration Mission Discovers New Planet" title="Space Exploration Mission Discovers New Planet" loading="lazy" referrerpolicy="no-referrer" decoding="async" crossorigin="anonymous">

        NASA's latest space exploration mission has discovered a potentially habitable planet in a nearby star system. The planet, designated Kepler-442b, shows promising signs of having liquid water and a stable atmosphere. This discovery opens up new possibilities for future space exploration and the search for extraterrestrial life.

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
          <td>🖼️ Image</td>
          <td><a href="https://example.com/images/space-discovery.jpg" target="_blank" rel="nofollow noopener noreferrer">https://example.com/images/space-discovery.jpg</a></td>
          <td><a href="https://example.com/images/space-discovery.jpg" target="_blank" rel="nofollow noopener noreferrer">View</a> |
        <a href="https://example.com/images/space-discovery.jpg" target="_blank" rel="nofollow noopener noreferrer" download="">Download</a></td>
        </tr>
          </tbody>
        </table>
        </details>
      HTML
      <<~HTML.chomp,
        <img src="https://example.com/images/cancer-research.jpg" alt="Medical Breakthrough Offers Hope for Cancer Patients" title="Medical Breakthrough Offers Hope for Cancer Patients" loading="lazy" referrerpolicy="no-referrer" decoding="async" crossorigin="anonymous">

        Researchers have developed a new immunotherapy treatment that shows remarkable success in treating previously untreatable forms of cancer. The treatment uses the patient's own immune system to target cancer cells. Clinical trials have shown a 75% success rate in patients with advanced-stage cancer, offering new hope for millions of patients worldwide.

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
          <td>🖼️ Image</td>
          <td><a href="https://example.com/images/cancer-research.jpg" target="_blank" rel="nofollow noopener noreferrer">https://example.com/images/cancer-research.jpg</a></td>
          <td><a href="https://example.com/images/cancer-research.jpg" target="_blank" rel="nofollow noopener noreferrer">View</a> |
        <a href="https://example.com/images/cancer-research.jpg" target="_blank" rel="nofollow noopener noreferrer" download="">Download</a></td>
        </tr>
          </tbody>
        </table>
        </details>
      HTML
      <<~HTML.chomp,
        <img src="https://example.com/images/renewable-energy.jpg" alt="Renewable Energy Reaches New Milestone" title="Renewable Energy Reaches New Milestone" loading="lazy" referrerpolicy="no-referrer" decoding="async" crossorigin="anonymous">

        Renewable energy sources now account for over 50% of global electricity generation for the first time in history. This milestone represents a major shift towards sustainable energy production. Solar and wind power have led this transformation, with costs dropping dramatically over the past decade and efficiency continuing to improve.

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
          <td>🖼️ Image</td>
          <td><a href="https://example.com/images/renewable-energy.jpg" target="_blank" rel="nofollow noopener noreferrer">https://example.com/images/renewable-energy.jpg</a></td>
          <td><a href="https://example.com/images/renewable-energy.jpg" target="_blank" rel="nofollow noopener noreferrer">View</a> |
        <a href="https://example.com/images/renewable-energy.jpg" target="_blank" rel="nofollow noopener noreferrer" download="">Download</a></td>
        </tr>
          </tbody>
        </table>
        </details>
      HTML
      <<~HTML.chomp,
        <img src="https://example.com/images/cybersecurity.jpg" alt="Cybersecurity Threats Reach All-Time High" title="Cybersecurity Threats Reach All-Time High" loading="lazy" referrerpolicy="no-referrer" decoding="async" crossorigin="anonymous">

        Cybersecurity experts report that cyber threats have reached unprecedented levels, with sophisticated attacks targeting critical infrastructure and government systems worldwide. Organizations are being urged to implement stronger security measures and invest in advanced threat detection systems to protect against these evolving risks.

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
          <td>🖼️ Image</td>
          <td><a href="https://example.com/images/cybersecurity.jpg" target="_blank" rel="nofollow noopener noreferrer">https://example.com/images/cybersecurity.jpg</a></td>
          <td><a href="https://example.com/images/cybersecurity.jpg" target="_blank" rel="nofollow noopener noreferrer">View</a> |
        <a href="https://example.com/images/cybersecurity.jpg" target="_blank" rel="nofollow noopener noreferrer" download="">Download</a></td>
        </tr>
          </tbody>
        </table>
        </details>
      HTML
    ]
  end

  let(:expected_categories) do
    [
      ['Technology', 'Artificial Intelligence', 'Machine Learning', 'Innovation'],
      ['Environment', 'Climate Change', 'Sustainability', 'Policy'],
      ['Science', 'Space Exploration', 'Astronomy', 'Discovery'],
      ['Health', 'Cancer Research', 'Immunotherapy', 'Medical Breakthrough'],
      ['Energy', 'Renewable Energy', 'Solar Power', 'Wind Power'],
      ['Security', 'Cybersecurity', 'Threat Detection', 'Infrastructure Security']
    ]
  end

  let(:expected_pubdates) do
    [
      'Mon, 15 Jan 2024 14:30:00 +0000',
      'Sun, 14 Jan 2024 09:15:00 +0000',
      'Sat, 13 Jan 2024 16:45:00 +0000',
      'Fri, 12 Jan 2024 11:20:00 +0000',
      'Thu, 11 Jan 2024 15:10:00 +0000',
      'Wed, 10 Jan 2024 08:30:00 +0000'
    ]
  end

  let(:expected_enclosures) do
    [
      ['https://example.com/images/ai-breakthrough.jpg', 'image/jpeg', 0],
      ['https://example.com/images/climate-summit.jpg', 'image/jpeg', 0],
      ['https://example.com/images/space-discovery.jpg', 'image/jpeg', 0],
      ['https://example.com/images/cancer-research.jpg', 'image/jpeg', 0],
      ['https://example.com/images/renewable-energy.jpg', 'image/jpeg', 0],
      ['https://example.com/images/cybersecurity.jpg', 'image/jpeg', 0]
    ]
  end

  it 'loads channel metadata from the configuration file' do
    expect(feed.channel.title).to eq('ACME JSON API Site News')
    expect(feed.channel.link).to eq('https://example.com/posts')
  end

  it 'materialises feed items directly from the API payload', :aggregate_failures do
    expect(items.size).to eq(expected_titles.size)
    expect(items.map(&:title)).to eq(expected_titles)
    expect(items.map(&:description)).to eq(expected_descriptions)
    expect(items.map { |item| item.pubDate.rfc2822 }).to eq(expected_pubdates)
  end

  it 'exposes category and tag metadata as discrete RSS category entries' do
    expect(items.map { |item| item.categories.map(&:content) })
      .to eq(expected_categories)
  end

  it 'omits item links when no selector is configured' do
    expect(items.map(&:link)).to all(be_nil)
  end

  it 'attaches a media enclosure to every entry' do
    actual_enclosures = items.map do |item|
      enclosure = item.enclosure
      [enclosure&.url, enclosure&.type, enclosure&.length]
    end
    expect(actual_enclosures).to eq(expected_enclosures)
  end
end
