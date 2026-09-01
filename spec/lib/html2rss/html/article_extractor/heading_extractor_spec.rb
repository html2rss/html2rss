# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Html::ArticleExtractor::HeadingExtractor do
  describe '.call' do
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
