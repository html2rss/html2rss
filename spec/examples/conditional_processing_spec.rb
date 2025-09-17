# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Conditional Processing Configuration' do
  let(:config_file) { File.join(%w[spec examples conditional_processing_site.yml]) }
  let(:html_file) { File.join(%w[spec examples conditional_processing_site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  describe 'configuration loading' do
    it_behaves_like 'validates configuration structure'

    it 'has correct post-processing configuration', :aggregate_failures do
      description_post_process = config[:selectors][:description][:post_process]
      expect(description_post_process).to be_an(Array)
      expect(description_post_process.first).to include(:name, :string)

      published_at_post_process = config[:selectors][:published_at][:post_process]
      expect(published_at_post_process).to be_an(Array)
      expect(published_at_post_process.first).to include(:name)
    end

    it 'includes status in categories' do
      expect(config[:selectors][:categories]).to include('status')
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      mock_request_service_with_html_fixture('conditional_processing_site', 'https://example.com')

      Html2rss.feed(config)
    end

    let(:items) { feed.items }
    let(:titles) { items.map(&:title) }

    it_behaves_like 'generates valid RSS feed'
    it_behaves_like 'extracts valid item content'
    it_behaves_like 'extracts valid published dates'

    it 'extracts status information as categories' do
      items_with_status = items.select do |item|
        item.categories.any? { |cat| cat.content.is_a?(String) }
      end
      expect(items_with_status.size).to be > 0
    end

    it 'validates template syntax is correct', :aggregate_failures do
      template_config = config[:selectors][:description][:post_process].first
      expect(template_config).to have_key(:string)
      expect(template_config).not_to have_key(:template)
    end
  end
end
