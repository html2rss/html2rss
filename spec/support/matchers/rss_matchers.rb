# frozen_string_literal: true

# Custom RSpec matchers for HTML2RSS testing
# These matchers provide clear, descriptive assertions for RSS feed validation
# with helpful failure messages for better debugging experience.

RSpec::Matchers.define :be_a_valid_rss_feed do
  match do |feed|
    feed.is_a?(RSS::Rss) &&
      feed.channel.is_a?(RSS::Rss::Channel) &&
      feed.channel.title.is_a?(String) &&
      !feed.channel.title.strip.empty? &&
      feed.channel.link.is_a?(String) &&
      !feed.channel.link.strip.empty?
  end

  failure_message do |feed|
    if feed.nil?
      'expected a valid RSS feed, but got nil'
    elsif !feed.is_a?(RSS::Rss)
      "expected a valid RSS feed, but got #{feed.class}"
    elsif !feed.channel.is_a?(RSS::Rss::Channel)
      "expected RSS feed to have a valid channel, but got #{feed.channel.class}"
    elsif !feed.channel.title.is_a?(String) || feed.channel.title.strip.empty?
      "expected RSS feed channel to have a non-empty title, but got: #{feed.channel.title.inspect}"
    elsif !feed.channel.link.is_a?(String) || feed.channel.link.strip.empty?
      "expected RSS feed channel to have a non-empty link, but got: #{feed.channel.link.inspect}"
    else
      'expected a valid RSS feed, but validation failed for unknown reason'
    end
  end

  description do
    'be a valid RSS feed with proper channel, title, and link'
  end
end

RSpec::Matchers.define :have_valid_items do |expected_count: nil|
  match do |feed|
    return false unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    if expected_count
      return false unless feed.items.size == expected_count
    elsif feed.items.empty?
      return false
    end

    # An item is valid if it's a proper RSS item and has either a title or description
    feed.items.all? do |item|
      item.is_a?(RSS::Rss::Channel::Item) &&
        ((item.title.is_a?(String) && !item.title.strip.empty?) ||
         (item.description.is_a?(String) && !item.description.strip.empty?))
    end
  end

  failure_message do |feed|
    if !feed.is_a?(RSS::Rss)
      "expected a valid RSS feed, but got #{feed.class}"
    elsif !feed.items.is_a?(Array)
      "expected RSS feed to have items array, but got #{feed.items.class}"
    elsif expected_count && feed.items.size != expected_count
      "expected RSS feed to have #{expected_count} items, but got #{feed.items.size}"
    elsif feed.items.empty?
      'expected RSS feed to have at least one item, but got none'
    else
      invalid_items = feed.items.reject do |item|
        item.is_a?(RSS::Rss::Channel::Item) &&
          ((item.title.is_a?(String) && !item.title.strip.empty?) ||
           (item.description.is_a?(String) && !item.description.strip.empty?))
      end

      # Provide more detailed debugging information
      if invalid_items.any?
        sample_invalid = invalid_items.first
        <<~MSG
          expected all RSS items to be valid, but found #{invalid_items.size} invalid items.
          Sample invalid item: title=#{sample_invalid.title.inspect},
          description=#{sample_invalid.description.inspect},
          class=#{sample_invalid.class}
        MSG
      else
        "expected all RSS items to be valid, but found #{invalid_items.size} invalid items"
      end
    end
  end

  description do
    if expected_count
      "have #{expected_count} valid RSS items"
    else
      'have valid RSS items'
    end
  end
end

RSpec::Matchers.define :have_valid_titles do
  match do |feed|
    return false unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    # Only check items that have titles - items without titles are valid
    items_with_titles = feed.items.reject { |item| item.title.nil? }
    return true if items_with_titles.empty? # No items with titles is valid

    items_with_titles.all? do |item|
      item.title.is_a?(String) && !item.title.strip.empty?
    end
  end

  failure_message do |feed|
    if !feed.is_a?(RSS::Rss)
      "expected a valid RSS feed, but got #{feed.class}"
    elsif !feed.items.is_a?(Array)
      "expected RSS feed to have items array, but got #{feed.items.class}"
    else
      items_with_titles = feed.items.reject { |item| item.title.nil? }
      invalid_titles = items_with_titles.reject do |item|
        item.title.is_a?(String) && !item.title.strip.empty?
      end
      <<~MSG
        expected all RSS items with titles to have valid titles,
        but found #{invalid_titles.size} items with invalid titles
      MSG
    end
  end

  description do
    'have valid titles for RSS items that have titles'
  end
end

RSpec::Matchers.define :have_valid_descriptions do
  match do |feed|
    return false unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    # Only check items that have descriptions - items without descriptions are valid
    items_with_descriptions = feed.items.reject { |item| item.description.nil? }
    return true if items_with_descriptions.empty? # No items with descriptions is valid

    items_with_descriptions.all? do |item|
      item.description.is_a?(String) && !item.description.strip.empty?
    end
  end

  failure_message do |feed|
    if !feed.is_a?(RSS::Rss)
      "expected a valid RSS feed, but got #{feed.class}"
    elsif !feed.items.is_a?(Array)
      "expected RSS feed to have items array, but got #{feed.items.class}"
    else
      items_with_descriptions = feed.items.reject { |item| item.description.nil? }
      invalid_descriptions = items_with_descriptions.reject do |item|
        item.description.is_a?(String) && !item.description.strip.empty?
      end
      <<~MSG
        expected all RSS items with descriptions to have valid descriptions,
        but found #{invalid_descriptions.size} items with invalid descriptions
      MSG
    end
  end

  description do
    'have valid descriptions for RSS items that have descriptions'
  end
end

RSpec::Matchers.define :have_valid_links do
  match do |feed|
    return false unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    # Only check items that have links - items without links are valid
    items_with_links = feed.items.reject { |item| item.link.nil? }
    return true if items_with_links.empty? # No items with links is valid

    items_with_links.all? do |item|
      item.link.is_a?(String) && !item.link.strip.empty?
    end
  end

  failure_message do |feed|
    if !feed.is_a?(RSS::Rss)
      "expected a valid RSS feed, but got #{feed.class}"
    elsif !feed.items.is_a?(Array)
      "expected RSS feed to have items array, but got #{feed.items.class}"
    else
      items_with_links = feed.items.reject { |item| item.link.nil? }
      invalid_links = items_with_links.reject do |item|
        item.link.is_a?(String) && !item.link.strip.empty?
      end
      "expected all RSS items with links to have valid links, but found #{invalid_links.size} items with invalid links"
    end
  end

  description do
    'have valid links for RSS items that have links'
  end
end

RSpec::Matchers.define :have_valid_published_dates do
  match do |feed|
    return false unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    feed.items.all? do |item|
      item.pubDate.nil? || item.pubDate.is_a?(Time)
    end
  end

  failure_message do |feed|
    if !feed.is_a?(RSS::Rss)
      "expected a valid RSS feed, but got #{feed.class}"
    elsif !feed.items.is_a?(Array)
      "expected RSS feed to have items array, but got #{feed.items.class}"
    else
      invalid_dates = feed.items.reject do |item|
        item.pubDate.nil? || item.pubDate.is_a?(Time)
      end
      <<~MSG
        expected all RSS items to have valid published dates (Time or nil),
        but found #{invalid_dates.size} items with invalid dates
      MSG
    end
  end

  description do
    'have valid published dates for all RSS items'
  end
end

RSpec::Matchers.define :have_valid_guids do
  match do |feed|
    return false unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    feed.items.all? do |item|
      item.guid.nil? ||
        (item.guid.is_a?(RSS::Rss::Channel::Item::Guid) &&
         item.guid.content.is_a?(String) &&
         !item.guid.content.strip.empty?)
    end
  end

  failure_message do |feed|
    if !feed.is_a?(RSS::Rss)
      "expected a valid RSS feed, but got #{feed.class}"
    elsif !feed.items.is_a?(Array)
      "expected RSS feed to have items array, but got #{feed.items.class}"
    else
      invalid_guids = feed.items.reject do |item|
        item.guid.nil? ||
          (item.guid.is_a?(RSS::Rss::Channel::Item::Guid) &&
           item.guid.content.is_a?(String) &&
           !item.guid.content.strip.empty?)
      end
      "expected all RSS items to have valid GUIDs, but found #{invalid_guids.size} items with invalid GUIDs"
    end
  end

  description do
    'have valid GUIDs for all RSS items'
  end
end

RSpec::Matchers.define :have_categories do |expected_categories: []|
  match do |feed|
    return false unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    if expected_categories.empty?
      # Just check that items have categories
      feed.items.any? { |item| item.categories.any? }
    else
      # Check that items have the expected categories
      feed.items.any? do |item|
        item.categories.any? do |category|
          expected_categories.any? { |expected| category.content.to_s.include?(expected) }
        end
      end
    end
  end

  failure_message do |feed|
    if !feed.is_a?(RSS::Rss)
      "expected a valid RSS feed, but got #{feed.class}"
    elsif !feed.items.is_a?(Array)
      "expected RSS feed to have items array, but got #{feed.items.class}"
    elsif expected_categories.empty?
      'expected RSS feed to have items with categories, but found none'
    else
      "expected RSS feed to have items with categories containing: #{expected_categories.join(', ')}, but found none"
    end
  end

  description do
    if expected_categories.empty?
      'have items with categories'
    else
      "have items with categories containing: #{expected_categories.join(', ')}"
    end
  end
end

RSpec::Matchers.define :have_enclosures do |expected_type: nil|
  match do |feed|
    return false unless feed.is_a?(RSS::Rss) && feed.items.is_a?(Array)

    items_with_enclosures = feed.items.select(&:enclosure)

    if expected_type
      items_with_enclosures.any? do |item|
        item.enclosure.type.include?(expected_type)
      end
    else
      items_with_enclosures.any?
    end
  end

  failure_message do |feed|
    if !feed.is_a?(RSS::Rss)
      "expected a valid RSS feed, but got #{feed.class}"
    elsif !feed.items.is_a?(Array)
      "expected RSS feed to have items array, but got #{feed.items.class}"
    elsif expected_type
      "expected RSS feed to have items with #{expected_type} enclosures, but found none"
    else
      'expected RSS feed to have items with enclosures, but found none'
    end
  end

  description do
    if expected_type
      "have items with #{expected_type} enclosures"
    else
      'have items with enclosures'
    end
  end
end
