# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Html::ArticleExtractor::HeadingExtractor do
  describe '.call' do
    it 'prefers the numerically lowest heading tag (h1 over h2/h3)' do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <div class="card">
          <h3>Tertiary</h3>
          <h2>Secondary</h2>
          <h1>Primary title</h1>
        </div>
      HTML
      container = Nokogiri::HTML(html).at_css('.card')

      heading = described_class.call(container, fallback_anchorless: false, selected_anchor: nil)

      expect(heading.name).to eq('h1')
    end

    it 'among equal heading levels prefers the longest text' do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <div class="card">
          <h2>Short</h2>
          <h2>This is the longer heading text</h2>
          <h3>Lower level ignored</h3>
        </div>
      HTML
      container = Nokogiri::HTML(html).at_css('.card')

      heading = described_class.call(container, fallback_anchorless: false, selected_anchor: nil)

      expect(heading.text).to eq('This is the longer heading text')
    end

    it 'prefers aria-label when no heading tags are present' do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <div class="card">
          <a href="/story" aria-label="Breaking story headline">icon</a>
        </div>
      HTML
      container = Nokogiri::HTML(html).at_css('.card')

      heading = described_class.call(container, fallback_anchorless: true, selected_anchor: nil)

      expect(heading['aria-label']).to eq('Breaking story headline')
    end

    it 'falls back to title attribute after aria-label candidates are empty' do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <div class="card">
          <a href="/story" title="Story from title attribute">icon</a>
        </div>
      HTML
      container = Nokogiri::HTML(html).at_css('.card')

      heading = described_class.call(container, fallback_anchorless: true, selected_anchor: nil)

      expect(heading['title']).to eq('Story from title attribute')
    end

    it 'returns nil when no heading, label, or fallback candidate exists', :aggregate_failures do
      container = Nokogiri::HTML('<div class="card"><span>plain text</span></div>').at_css('.card')

      expect(described_class.call(container, fallback_anchorless: true, selected_anchor: nil)).to be_nil
      expect(described_class.call(container, fallback_anchorless: false, selected_anchor: nil)).to be_nil
    end

    it 'skips blank aria-label and title attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <div class="card">
          <a aria-label="   " title="Real title">icon</a>
          <a aria-label="Labelled">other</a>
        </div>
      HTML
      container = Nokogiri::HTML(html).at_css('.card')

      heading = described_class.call(container, fallback_anchorless: true, selected_anchor: nil)

      expect(heading['aria-label']).to eq('Labelled')
    end

    it 'uses title attribute only when every aria-label is blank', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <div class="card">
          <a aria-label="" title="Title wins">icon</a>
        </div>
      HTML
      container = Nokogiri::HTML(html).at_css('.card')

      heading = described_class.call(container, fallback_anchorless: false, selected_anchor: nil)

      expect(heading['title']).to eq('Title wins')
    end

    it 'falls back to the first non-empty strong, bold, or title-classed element', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <div class="card">
          <strong>   </strong>
          <span class="story-title">Class based title</span>
          <b>Bold later</b>
        </div>
      HTML
      container = Nokogiri::HTML(html).at_css('.card')

      heading = described_class.call(container, fallback_anchorless: true, selected_anchor: nil)

      expect(heading.text).to eq('Class based title')
    end

    it 'matches font-bold and font-semibold classes as fallback candidates', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <div class="card">
          <div class="font-semibold">Semibold item</div>
        </div>
      HTML
      container = Nokogiri::HTML(html).at_css('.card')

      heading = described_class.call(container, fallback_anchorless: true, selected_anchor: nil)

      expect(heading.text).to eq('Semibold item')
    end

    it 'skips the fallback search when an anchor is already selected', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <div class="card">
          <strong>Bold text</strong>
          <a href="/story">link</a>
        </div>
      HTML
      container = Nokogiri::HTML(html).at_css('.card')
      anchor = container.at_css('a')

      expect(described_class.call(container, fallback_anchorless: true, selected_anchor: anchor)).to be_nil
    end

    it 'skips the fallback search when anchorless fallback is disabled', :aggregate_failures do
      container = Nokogiri::HTML('<div class="card"><strong>Bold text</strong></div>').at_css('.card')

      expect(described_class.call(container, fallback_anchorless: false, selected_anchor: nil)).to be_nil
    end

    it 'ranks equal-level headings by text length rather than document order', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      html = <<~HTML
        <div class="card">
          <h2>A considerably longer heading first</h2>
          <h2>Short</h2>
        </div>
      HTML
      container = Nokogiri::HTML(html).at_css('.card')

      heading = described_class.call(container, fallback_anchorless: false, selected_anchor: nil)

      expect(heading.text).to eq('A considerably longer heading first')
    end
  end
end
