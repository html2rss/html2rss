# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Conditional Processing Configuration' do
  let(:config_file) { File.join(%w[spec fixtures conditional-processing-site.test.yml]) }
  let(:html_file) { File.join(%w[spec fixtures conditional-processing-site.html]) }
  let(:config) { Html2rss.config_from_yaml_file(config_file) }

  # Extract array literals to avoid Performance/CollectionLiteralInLoop violations
  let(:expected_statuses) { %w[Published Draft Archived Pending] }

  describe 'configuration loading' do
    it 'loads the configuration correctly', :aggregate_failures do
      expect(config).to be_a(Hash)
      expect(config[:channel][:url]).to eq('https://conditional-processing-site.com')
      expect(config[:channel][:title]).to eq('Conditional Processing Site News')
      expect(config[:selectors][:items][:selector]).to eq('.item')
      expect(config[:selectors][:title][:selector]).to eq('h2')
      expect(config[:selectors][:status][:selector]).to eq('.status')
      expect(config[:selectors][:description][:selector]).to eq('.content')
      expect(config[:selectors][:published_at][:selector]).to eq('.date')
      expect(config[:selectors][:categories]).to include('status')
    end

    it 'has correct post-processing configuration', :aggregate_failures do
      description_post_process = config[:selectors][:description][:post_process]
      expect(description_post_process).to include(
        { name: 'template', string: '[Status: %<status>s] %<self>s' }
      )

      published_at_post_process = config[:selectors][:published_at][:post_process]
      expect(published_at_post_process).to include(
        { name: 'parse_time' }
      )
    end

    it 'includes status in categories' do
      expect(config[:selectors][:categories]).to include('status')
    end
  end

  describe 'RSS feed generation' do
    subject(:feed) do
      # Mock the request service to return our HTML fixture
      mock_request_service_with_html_fixture('conditional_processing_site', 'https://conditional-processing-site.com')

      Html2rss.feed(config)
    end

    it 'generates a valid RSS feed', :aggregate_failures do
      expect(feed).to be_a(RSS::Rss)
      expect(feed.channel.title).to eq('Conditional Processing Site News')
      expect(feed.channel.link).to eq('https://conditional-processing-site.com')
    end

    it 'extracts the correct number of items' do
      expect(feed.items.size).to eq(6)
    end

    describe 'item extraction' do
      let(:items) { feed.items }

      it 'extracts titles correctly using h2 selector', :aggregate_failures do
        titles = items.map(&:title)
        expect(titles).to all(be_a(String))
        expect(titles).to include('Breaking News: ACME Corp\'s New Debugging Tool')
        expect(titles).to include('Draft Article: ACME Corp\'s Green Coding Initiative')
        expect(titles).to include('Archived Article: ACME Corp\'s Economic Analysis of Bug Fixes')
        expect(titles).to include('ACME Corp\'s Developer Health and Wellness Guide')
        expect(titles).to include('Pending Article: ACME Corp\'s Annual Code Golf Tournament')
        expect(titles).to include('ACME Corp\'s Article Without Status (Status: Unknown)')
      end

      it 'extracts status information as categories', :aggregate_failures do
        # Items with status should have status categories
        items_with_status = items.select do |item|
          item.categories.any? do |cat|
            expected_statuses.include?(cat.content)
          end
        end
        expect(items_with_status.size).to eq(5) # 5 items have status

        items_with_status.each do |item|
          expect(item.categories).not_to be_nil
          status_categories = item.categories.select do |cat|
            expected_statuses.include?(cat.content)
          end
          expect(status_categories).not_to be_empty
        end

        # One item should have no categories (no status field)
        items_without_status = items.select { |item| item.categories.empty? }
        expect(items_without_status.size).to eq(1)
        expect(items_without_status.first.title).to eq('ACME Corp\'s Article Without Status (Status: Unknown)')
      end

      it 'extracts published dates correctly', :aggregate_failures do
        items_with_time = items.select(&:pubDate)
        expect(items_with_time.size).to eq(6) # All items have dates

        # Check that dates are parsed correctly
        items_with_time.each do |item|
          expect(item.pubDate).to be_a(Time)
          expect(item.pubDate.year).to eq(2024)
        end
      end
    end

    describe 'conditional processing with templates' do
      let(:items) { feed.items }

      it 'applies template processing to descriptions', :aggregate_failures do
        descriptions = items.map(&:description)

        # All descriptions should be strings
        expect(descriptions).to all(be_a(String))

        # Descriptions should contain status information from template
        expect(descriptions).to all(match(/\[Status: .*\]/))
      end

      it 'includes correct status values in descriptions', :aggregate_failures do
        # Find items by their expected status
        published_items = items.select { |item| item.description.include?('[Status: Published]') }
        draft_items = items.select { |item| item.description.include?('[Status: Draft]') }
        archived_items = items.select { |item| item.description.include?('[Status: Archived]') }
        pending_items = items.select { |item| item.description.include?('[Status: Pending]') }

        expect(published_items.size).to eq(2) # 2 published items
        expect(draft_items.size).to eq(1)    # 1 draft item
        expect(archived_items.size).to eq(1) # 1 archived item
        expect(pending_items.size).to eq(1)  # 1 pending item
      end

      it 'handles items without status gracefully', :aggregate_failures do
        # Find the item without status
        no_status_items = items.select { |item| item.description.include?('[Status: ]') }
        expect(no_status_items.size).to eq(1) # 1 item without status

        # The template should still work but with empty status
        no_status_items.each do |item|
          expect(item.description).to include('[Status: ]')
        end
      end

      it 'preserves original content in template processing', :aggregate_failures do
        items.each do |item|
          # The description should contain both the status prefix and original content
          expect(item.description).to match(/\[Status: .*\].+/)

          # Should not just be the status, but include the actual content
          expect(item.description.length).to be > 50
        end
      end
    end

    describe 'status-based categorization' do
      let(:items) { feed.items }

      it 'includes status as categories', :aggregate_failures do
        # Items with status should have status categories
        items_with_status = items.select do |item|
          item.categories.any? do |cat|
            expected_statuses.include?(cat.content)
          end
        end
        expect(items_with_status.size).to eq(5) # 5 items have status

        items_with_status.each do |item|
          expect(item.categories).not_to be_nil
          status_categories = item.categories.select do |cat|
            expected_statuses.include?(cat.content)
          end
          expect(status_categories).not_to be_empty
        end
      end

      it 'has different status values for different items', :aggregate_failures do
        status_values = items.map do |item|
          status_cat = item.categories.find do |cat|
            expected_statuses.include?(cat.content)
          end
          status_cat ? status_cat.content : 'No Status'
        end

        expect(status_values).to include('Published')
        expect(status_values).to include('Draft')
        expect(status_values).to include('Archived')
        expect(status_values).to include('Pending')
        expect(status_values).to include('No Status')
      end
    end

    describe 'template post-processing validation' do
      let(:items) { feed.items }

      it 'validates template syntax is correct' do
        # The template should use the correct Ruby string interpolation syntax
        template_config = config[:selectors][:description][:post_process].first
        expect(template_config[:string]).to eq('[Status: %<status>s] %<self>s')
      end

      it 'applies template processing to all items' do
        items.each do |item|
          # Each description should start with the status prefix
          expect(item.description).to start_with('[Status: ')
        end
      end

      it 'handles missing status values in template' do
        # Items without status should show empty status in template
        no_status_items = items.select { |item| item.description.include?('[Status: ]') }
        expect(no_status_items.size).to eq(1)
      end
    end

    describe 'configuration issues' do
      it 'identifies the template parameter issue', :aggregate_failures do
        # The original config had: template: "[Status: %{status}] %{self}"
        # But should be: string: "[Status: %<status>s] %<self>s"
        template_config = config[:selectors][:description][:post_process].first

        # Should use 'string' parameter, not 'template'
        expect(template_config).to have_key(:string)
        expect(template_config).not_to have_key(:template)

        # Should use correct Ruby syntax
        expect(template_config[:string]).to eq('[Status: %<status>s] %<self>s')
      end

      it 'validates that the configuration is complete', :aggregate_failures do
        # Should have all required sections
        expect(config[:channel]).not_to be_nil
        expect(config[:selectors]).not_to be_nil

        # Should have required channel fields
        expect(config[:channel][:url]).not_to be_nil
        expect(config[:channel][:title]).not_to be_nil

        # Should have conditional processing selectors
        expect(config[:selectors][:status]).not_to be_nil
        expect(config[:selectors][:description]).not_to be_nil
        expect(config[:selectors][:description][:post_process]).not_to be_nil
      end

      it 'validates template post-processor configuration', :aggregate_failures do
        template_config = config[:selectors][:description][:post_process].first
        expect(template_config[:name]).to eq('template')
        expect(template_config[:string]).to be_a(String)
        expect(template_config[:string]).to include('%<status>s')
        expect(template_config[:string]).to include('%<self>s')
      end
    end
  end
end
