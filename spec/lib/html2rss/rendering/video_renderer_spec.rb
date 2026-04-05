# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Rendering::VideoRenderer do
  describe '#to_html' do
    it 'renders compact video html with escaped attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      renderer = described_class.new(url: 'https://example.com/video.mp4?x=1&y=2', type: 'video/mp4')
      html = renderer.to_html
      expected_html = [
        '<video controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous" playsinline>',
        '<source src="https://example.com/video.mp4?x=1&amp;y=2" type="video/mp4">',
        '</video>'
      ].join

      expect(html).to eq(expected_html)
      expect(html).not_to include("\n")
    end
  end
end
