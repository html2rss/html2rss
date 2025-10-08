# frozen_string_literal: true

require 'spec_helper'
require 'time'

RSpec.describe 'Conditional Processing Configuration' do
  subject(:feed) do
    mock_request_service_with_html_fixture('conditional_processing_site', 'https://example.com')
    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples conditional_processing_site.yml]) }
  let(:html_file) { File.join(%w[spec examples conditional_processing_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }
  let(:channel_url) { config.dig(:channel, :url) }
  let(:items) { feed.items }

  let(:expected_titles) do
    [
      "Breaking News: ACME Corp's New Debugging Tool",
      "Draft Article: ACME Corp's Green Coding Initiative",
      "Archived Article: ACME Corp's Economic Analysis of Bug Fixes",
      "ACME Corp's Developer Health and Wellness Guide",
      "Pending Article: ACME Corp's Annual Code Golf Tournament",
      "ACME Corp's Article Without Status (Status: Unknown)"
    ]
  end

  let(:expected_links) do
    [
      'https://example.com/articles/technology-update',
      'https://example.com/articles/environmental-research',
      'https://example.com/articles/economic-analysis',
      'https://example.com/articles/health-wellness',
      'https://example.com/articles/sports-update',
      'https://example.com/articles/no-status'
    ]
  end

  let(:expected_descriptions) do
    [
      "[Status: Published] This is a published article about ACME Corp's latest debugging tool that can find bugs before they're even written. The content includes detailed information about recent developments in the tech industry. It's so advanced, it can predict when you'll need coffee. Additional content that provides more context and depth to the story. The tool also comes with a built-in rubber duck that actually quacks when you're stuck.",
      "[Status: Draft] This is a draft article about ACME Corp's environmental research into carbon-neutral coding practices. It contains preliminary findings and is not yet ready for publication. They're trying to make infinite loops actually infinite without using infinite energy. More content that will be refined before the final publication. The research shows that using tabs instead of spaces can reduce your carbon footprint by 0.0001%.",
      "[Status: Archived] This is an archived article about ACME Corp's economic analysis of bug fixes. It was previously published but is now archived for historical reference. The study found that 99% of bugs are caused by cosmic rays and the remaining 1% are caused by developers. Additional archived content that provides historical context. The research concluded that the most expensive bug in history was a missing semicolon that cost $1.2 billion.",
      "[Status: Published] This is a comprehensive health and wellness guide for developers. It provides expert recommendations for maintaining good health while coding. Remember: coffee is not a food group, but it is a lifestyle choice. Additional health tips and recommendations for readers. Pro tip: Standing desks are great, but standing on your head while coding is not recommended.",
      "[Status: Pending] This is a pending article about ACME Corp's annual code golf tournament. It's waiting for final approval before publication. The winner gets a lifetime supply of coffee and a rubber duck that never quacks. Content that will be reviewed and potentially modified before going live. The tournament features events like \"Write a sorting algorithm in one line\" and \"Debug this code blindfolded\".",
      "[Status: ] This article doesn't have a status field, so it should use a fallback or empty value in the template. It's like a function that returns void but actually returns null. This tests how the template handles missing values. In programming terms, this is the equivalent of a null pointer exception waiting to happen."
    ]
  end

  let(:expected_categories) do
    [
      ['Published'],
      ['Draft'],
      ['Archived'],
      ['Published'],
      ['Pending'],
      []
    ]
  end

  let(:expected_pubdates) do
    [
      'Mon, 15 Jan 2024 10:30:00 +0000',
      'Sun, 14 Jan 2024 14:20:00 +0000',
      'Sat, 13 Jan 2024 09:15:00 +0000',
      'Fri, 12 Jan 2024 08:30:00 +0000',
      'Thu, 11 Jan 2024 16:45:00 +0000',
      'Wed, 10 Jan 2024 12:00:00 +0000'
    ]
  end

  it 'publishes the configured channel metadata' do
    expect(feed.channel.title).to eq('ACME Conditional Processing Site News')
    expect(feed.channel.link).to eq('https://example.com')
  end

  it 'renders templated descriptions that expose the item status', :aggregate_failures do
    expect(items.map(&:description)).to eq(expected_descriptions)
    expect(items.map { |item| item.categories.map(&:content) }).to eq(expected_categories)
  end

  it 'produces stable item identifiers and links for every article' do
    expect(items.size).to eq(expected_titles.size)
    expect(items.map(&:title)).to eq(expected_titles)
    expect(items.map(&:link)).to eq(expected_links)
  end

  it 'parses ISO timestamps emitted by the editorial system' do
    expect(items.map { |item| item.pubDate.rfc2822 }).to eq(expected_pubdates)
  end

  it 'gracefully handles missing statuses in both the template output and category list' do
    empty_status_item = items.find { |item| item.title.include?('Without Status') }
    expect(empty_status_item.description).to start_with('[Status: ]')
    expect(empty_status_item.categories).to be_empty
  end
end
