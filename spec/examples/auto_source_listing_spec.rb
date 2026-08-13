# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Auto Source Listing Configuration', type: :example do
  subject(:feed) { generate_feed_from_config(config, config_name, :html) }

  let(:config_name) { 'auto_source_listing' }
  let(:config) { load_example_configuration(config_name) }
  let(:items) { feed.items }

  let(:expected_items) do
    [
      {
        title: 'First Auto Story Title',
        link: 'https://example.com/news/first-auto-story',
        description_includes: ['Teaser for the first story']
      },
      {
        title: 'Second Auto Story Title',
        link: 'https://example.com/news/second-auto-story',
        description_includes: ['Teaser for the second story']
      },
      {
        title: 'Third Auto Story Title',
        link: 'https://example.com/news/third-auto-story',
        description_includes: ['Teaser for the third story']
      }
    ]
  end

  it_behaves_like 'example feed channel metadata',
                  title: 'Auto Source Listing Demo',
                  link: 'https://example.com/'

  it 'builds feed items from HTML without manual selectors' do
    expect_feed_items(items, expected_items)
  end
end
