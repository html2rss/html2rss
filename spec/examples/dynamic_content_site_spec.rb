# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Dynamic Content Site Configuration' do
  let(:config_file) { File.join(%w[spec examples dynamic_content_site.yml]) }
  let(:html_file) { File.join(%w[spec examples dynamic_content_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  describe 'configuration loading' do
    it_behaves_like 'validates configuration structure'

    it 'has browserless strategy configured' do
      expect(config[:strategy]).to eq('browserless')
    end

    it 'has time zone configured' do
      expect(config[:channel][:time_zone]).to be_a(String)
    end

    it 'has href extractor for URLs' do
      expect(config[:selectors][:url][:extractor]).to eq('href')
    end

    it_behaves_like 'validates description post-processing'
    it_behaves_like 'validates published_at post-processing'
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      mock_request_service_with_html_fixture('dynamic_content_site', 'https://example.com/news')

      Html2rss.feed(config)
    end

    let(:items) { feed.items }

    it_behaves_like 'generates valid RSS feed'
    it_behaves_like 'extracts valid item content'
    it_behaves_like 'extracts valid published dates'

    it 'handles dynamic content loading', :aggregate_failures do
      expect(items.size).to be > 0

      items.each do |item|
        expect(item.title).not_to be_nil
        expect(item.link).not_to be_nil
        expect(item.description).not_to be_nil
        expect(item.pubDate).not_to be_nil
      end
    end

    it 'uses href extractor for URL extraction', :aggregate_failures do
      url_config = config[:selectors][:url]
      expect(url_config[:extractor]).to eq('href')
      expect(url_config[:selector]).to be_a(String)
    end
  end
end
