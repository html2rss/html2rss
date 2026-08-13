# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Html::Rendering::VideoRenderer do
  describe '#to_html' do
    it_behaves_like 'compact media renderer html',
                    tag: 'video',
                    url: 'https://example.com/video.mp4?x=1&y=2',
                    type: 'video/mp4',
                    open_tag: '<video controls preload="none" referrerpolicy="no-referrer" ' \
                              'crossorigin="anonymous" playsinline>'
  end
end
