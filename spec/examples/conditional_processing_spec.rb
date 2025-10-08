# frozen_string_literal: true

require 'spec_helper'
require 'time'

RSpec.describe 'Conditional Processing Configuration' do
  subject(:feed) do
    mock_request_service_with_html_fixture('conditional_processing_site', 'https://example.com')
    Html2rss.feed(config)
  end

  let(:config_file) { File.join(%w[spec examples conditional_processing_site.yml]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }
  let(:items) { feed.items }

  let(:expected_items) do
    [
      {
        title: "Breaking News: ACME Corp's New Debugging Tool",
        link: 'https://example.com/articles/technology-update',
        description_starts_with: '[Status: Published]',
        description_includes: [
          "latest debugging tool",
          'built-in rubber duck'
        ],
        categories: ['Published'],
        pub_date: 'Mon, 15 Jan 2024 10:30:00 +0000'
      },
      {
        title: "Draft Article: ACME Corp's Green Coding Initiative",
        link: 'https://example.com/articles/environmental-research',
        description_starts_with: '[Status: Draft]',
        description_includes: [
          'environmental research',
          'tabs instead of spaces'
        ],
        categories: ['Draft'],
        pub_date: 'Sun, 14 Jan 2024 14:20:00 +0000'
      },
      {
        title: "Archived Article: ACME Corp's Economic Analysis of Bug Fixes",
        link: 'https://example.com/articles/economic-analysis',
        description_starts_with: '[Status: Archived]',
        description_includes: [
          '99% of bugs are caused by cosmic rays',
          'missing semicolon that cost $1.2 billion'
        ],
        categories: ['Archived'],
        pub_date: 'Sat, 13 Jan 2024 09:15:00 +0000'
      },
      {
        title: "ACME Corp's Developer Health and Wellness Guide",
        link: 'https://example.com/articles/health-wellness',
        description_starts_with: '[Status: Published]',
        description_includes: [
          'coffee is not a food group',
          'Standing desks are great'
        ],
        categories: ['Published'],
        pub_date: 'Fri, 12 Jan 2024 08:30:00 +0000'
      },
      {
        title: "Pending Article: ACME Corp's Annual Code Golf Tournament",
        link: 'https://example.com/articles/sports-update',
        description_starts_with: '[Status: Pending]',
        description_includes: [
          'lifetime supply of coffee',
          'Debug this code blindfolded'
        ],
        categories: ['Pending'],
        pub_date: 'Thu, 11 Jan 2024 16:45:00 +0000'
      },
      {
        title: "ACME Corp's Article Without Status (Status: Unknown)",
        link: 'https://example.com/articles/no-status',
        description_starts_with: '[Status: ]',
        description_includes: [
          "doesn't have a status field",
          'null pointer exception'
        ],
        categories: [],
        pub_date: 'Wed, 10 Jan 2024 12:00:00 +0000'
      }
    ]
  end

  it 'publishes the configured channel metadata' do
    expect(feed.channel.title).to eq('ACME Conditional Processing Site News')
    expect(feed.channel.link).to eq('https://example.com')
  end

  it 'renders templated descriptions that expose the item status' do
    expect_feed_items(items, expected_items)
  end

  it 'gracefully handles missing statuses in both the template output and category list' do
    empty_status_item = items.find { |item| item.title.include?('Without Status') }
    expect(empty_status_item.description).to start_with('[Status: ]')
    expect(empty_status_item.categories).to be_empty
  end
end
