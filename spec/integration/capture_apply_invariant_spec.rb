# frozen_string_literal: true

# rubocop:disable RSpec/MultipleMemoizedHelpers

require 'spec_helper'
require 'tempfile'

# A config that capture emits must extract items from the page it was captured from. Capture writes only an
# items selector, so any default that leaves enhance off ships a config with nothing to fill title and url.
# rubocop:disable-next RSpec/DescribeClass -- integration invariant spec; lives under spec/integration/
RSpec.describe 'Capture then apply' do
  let(:origin) { 'https://example.com' }
  let(:stories) { (1..5).map { |i| ["Story #{i} about something long enough", "#{origin}/news/story-#{i}-long"] } }
  let(:cards) do
    stories.map do |title, href|
      "<article><h2><a href='#{href}'>#{title}</a></h2>" \
        '<p>Summary text that is reasonably long to look like an excerpt of the story.</p></article>'
    end.join
  end
  # The same stories as JSON-LD: admission folds each HTML copy into its JSON-LD twin as a duplicate URL.
  let(:json_ld) do
    elements = stories.each_with_index.map do |(headline, url), index|
      { '@type' => 'ListItem', 'position' => index + 1, 'item' => { '@type' => 'NewsArticle', headline:, url: } }
    end
    list = { '@context' => 'https://schema.org', '@type' => 'ItemList', 'itemListElement' => elements }
    "<script type='application/ld+json'>#{JSON.generate(list)}</script>"
  end
  let(:pages) do
    {
      plain: "<html><head><title>News</title></head><body><main>#{cards}</main></body></html>",
      with_drops: "<html><head><title>News</title>#{json_ld}</head><body><main>#{cards}</main></body></html>"
    }
  end
  # Captured configs replay the same local file on apply, so the files outlive the capture.
  let(:files) do
    pages.transform_values { |html| Tempfile.new(%w[listing .html]).tap { _1.write(html) }.tap(&:close) }
  end
  let(:captures) do
    files.transform_values do |file|
      Html2rss.capture("#{origin}/news/", strategy: :local_file, local_file_path: file.path, force: true)
    end
  end

  after { files.each_value(&:unlink) }

  it 'applies every captured config to at least one item', :aggregate_failures do
    captures.each do |name, capture|
      expect(capture.has_selectors).to be(true), "#{name}: capture emitted no selectors"
      expect(Html2rss.apply(capture.config).item_count).to be >= 1, "#{name}: #{capture.config[:selectors]}"
    end
  end

  it 'covers a listing whose admission drops used to turn enhance off' do
    expect(captures[:with_drops].admission_drops.values.sum).to be >= 3
  end
end

# rubocop:enable RSpec/MultipleMemoizedHelpers
