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
  end
end
