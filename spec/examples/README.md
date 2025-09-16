# HTML2RSS Examples

This directory contains practical examples of HTML2RSS configurations with their corresponding test files. These examples serve as both documentation and quality assurance for the HTML2RSS library.

## Structure

Each example consists of three files:
- `*_spec.rb` - RSpec test file demonstrating the configuration
- `*.yml` - YAML configuration file
- `*.html` or `*.json` - Sample data file used for testing

## Examples

### Combined Scraper Sources
- **Files**: `combined_scraper_sources_spec.rb`, `combined_scraper_sources.yml`, `combined_scraper_sources.html`
- **Purpose**: Demonstrates combining auto-source detection with manual selectors
- **Features**: Auto-source enhancement, custom GUID generation, gsub post-processing

### Conditional Processing
- **Files**: `conditional_processing_spec.rb`, `conditional_processing_site.yml`, `conditional_processing_site.html`
- **Purpose**: Shows how to handle conditional content processing
- **Features**: Template post-processing, status-based categorization

### Dynamic Content Site
- **Files**: `dynamic_content_site_spec.rb`, `dynamic_content_site.yml`, `dynamic_content_site.html`
- **Purpose**: Handles JavaScript-heavy sites using browserless strategy
- **Features**: Browserless strategy, HTML sanitization, time zone handling

### JSON API Site
- **Files**: `json_api_site_spec.rb`, `json_api_site.yml`, `json_api_site.json`
- **Purpose**: Scrapes data from JSON APIs
- **Features**: JSON parsing, nested selectors, HTML to Markdown conversion

### Media Enclosures
- **Files**: `media_enclosures_spec.rb`, `media_enclosures_site.yml`, `media_enclosures_site.html`
- **Purpose**: Handles podcast and video content with media enclosures
- **Features**: Audio/video enclosures, duration extraction, HTML to Markdown

### Multi-Language Site
- **Files**: `multilang_site_spec.rb`, `multilang_site.yml`, `multilang_site.html`
- **Purpose**: Processes multi-language content
- **Features**: Language detection, template processing, multi-language categorization

### Performance Optimized
- **Files**: `performance_optimized_spec.rb`, `performance_optimized_site.yml`, `performance_optimized_site.html`
- **Purpose**: Optimized selectors for better performance
- **Features**: Complex CSS selectors, exclusion patterns, time parsing

### Unreliable Site
- **Files**: `unreliable_site_spec.rb`, `unreliable_site.yml`, `unreliable_site.html`
- **Purpose**: Handles sites with inconsistent structure
- **Features**: Fallback selectors, content sanitization, URL parsing

## Usage

These examples can be used as:

1. **Documentation**: Learn how to configure HTML2RSS for different scenarios
2. **Testing**: Run the specs to verify HTML2RSS functionality
3. **Templates**: Copy and modify configurations for your own use cases

## Running the Examples

To run all examples:
```bash
bundle exec rspec spec/examples/
```

To run a specific example:
```bash
bundle exec rspec spec/examples/combined_scraper_sources_spec.rb
```

## Notes

- All spec files have been cleaned to focus on configuration structure rather than specific content values
- The examples demonstrate best practices for HTML2RSS configuration
- Each example is self-contained and can be run independently
