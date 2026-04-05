# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Rendering::PdfRenderer do
  describe '#to_html' do
    it 'renders compact iframe html with escaped src', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      renderer = described_class.new(url: 'https://example.com/doc.pdf?x=1&y=2')
      html = renderer.to_html
      expected_html = [
        '<iframe src="https://example.com/doc.pdf?x=1&amp;y=2" width="100%"',
        'height="75vh" sandbox="" referrerpolicy="no-referrer" loading="lazy"></iframe>'
      ].join(' ')

      expect(html).to eq(expected_html)
      expect(html).not_to include("\n")
    end
  end
end
