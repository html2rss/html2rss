# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Rendering::AudioRenderer do
  describe '#to_html' do
    it 'renders compact audio html with escaped attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      renderer = described_class.new(url: 'https://example.com/audio.mp3?x=1&y=2', type: 'audio/mpeg')
      html = renderer.to_html
      expected_html = [
        '<audio controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous">',
        '<source src="https://example.com/audio.mp3?x=1&amp;y=2" type="audio/mpeg">',
        '</audio>'
      ].join

      expect(html).to eq(expected_html)
      expect(html).not_to include("\n")
    end
  end
end
