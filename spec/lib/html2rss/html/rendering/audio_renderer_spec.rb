# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Html::Rendering::AudioRenderer do
  describe '#to_html' do
    it_behaves_like 'compact media renderer html',
                    tag: 'audio',
                    url: 'https://example.com/audio.mp3?x=1&y=2',
                    type: 'audio/mpeg',
                    open_tag: '<audio controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous">'
  end
end
