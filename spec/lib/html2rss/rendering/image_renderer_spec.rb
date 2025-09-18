# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Rendering::ImageRenderer do
  describe '#to_html' do
    context 'with valid title' do
      it 'renders an img tag with escaped title', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        renderer = described_class.new(url: 'https://example.com/image.jpg', title: 'Test & Title')

        expect(renderer.to_html).to include('src="https://example.com/image.jpg"')
        expect(renderer.to_html).to include('alt="Test &amp; Title"')
        expect(renderer.to_html).to include('title="Test &amp; Title"')
        expect(renderer.to_html).to include('loading="lazy"')
        expect(renderer.to_html).to include('referrerpolicy="no-referrer"')
        expect(renderer.to_html).to include('decoding="async"')
        expect(renderer.to_html).to include('crossorigin="anonymous"')
      end
    end

    context 'with nil title' do
      it 'renders an img tag with empty alt and title attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        renderer = described_class.new(url: 'https://example.com/image.jpg', title: nil)

        expect(renderer.to_html).to include('src="https://example.com/image.jpg"')
        expect(renderer.to_html).to include('alt=""')
        expect(renderer.to_html).to include('title=""')
        expect(renderer.to_html).to include('loading="lazy"')
        expect(renderer.to_html).to include('referrerpolicy="no-referrer"')
        expect(renderer.to_html).to include('decoding="async"')
        expect(renderer.to_html).to include('crossorigin="anonymous"')
      end
    end

    context 'with empty string title' do
      it 'renders an img tag with empty alt and title attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        renderer = described_class.new(url: 'https://example.com/image.jpg', title: '')

        expect(renderer.to_html).to include('src="https://example.com/image.jpg"')
        expect(renderer.to_html).to include('alt=""')
        expect(renderer.to_html).to include('title=""')
        expect(renderer.to_html).to include('loading="lazy"')
        expect(renderer.to_html).to include('referrerpolicy="no-referrer"')
        expect(renderer.to_html).to include('decoding="async"')
        expect(renderer.to_html).to include('crossorigin="anonymous"')
      end
    end

    context 'with special characters in title' do
      it 'properly escapes HTML special characters', :aggregate_failures do
        renderer = described_class.new(url: 'https://example.com/image.jpg', title: '<script>alert("xss")</script>')

        expect(renderer.to_html).to include('alt="&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;"')
        expect(renderer.to_html).to include('title="&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;"')
      end
    end
  end
end
