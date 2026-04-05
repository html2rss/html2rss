# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Rendering::ImageRenderer do
  describe '#to_html' do
    context 'with valid title' do
      it 'renders an img tag with escaped title', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        renderer = described_class.new(url: 'https://example.com/image.jpg', title: 'Test & Title')
        html = renderer.to_html

        expect(html).to include('src="https://example.com/image.jpg"')
        expect(html).to include('alt="Test &amp; Title"')
        expect(html).to include('title="Test &amp; Title"')
        expect(html).to include('loading="lazy"')
        expect(html).to include('referrerpolicy="no-referrer"')
        expect(html).to include('decoding="async"')
        expect(html).to include('crossorigin="anonymous"')
        expect(html).not_to include("\n")
      end
    end

    context 'with nil title' do
      it 'renders an img tag with empty alt and title attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        renderer = described_class.new(url: 'https://example.com/image.jpg', title: nil)
        html = renderer.to_html

        expect(html).to include('src="https://example.com/image.jpg"')
        expect(html).to include('alt=""')
        expect(html).to include('title=""')
        expect(html).to include('loading="lazy"')
        expect(html).to include('referrerpolicy="no-referrer"')
        expect(html).to include('decoding="async"')
        expect(html).to include('crossorigin="anonymous"')
        expect(html).not_to include("\n")
      end
    end

    context 'with empty string title' do
      it 'renders an img tag with empty alt and title attributes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        renderer = described_class.new(url: 'https://example.com/image.jpg', title: '')
        html = renderer.to_html

        expect(html).to include('src="https://example.com/image.jpg"')
        expect(html).to include('alt=""')
        expect(html).to include('title=""')
        expect(html).to include('loading="lazy"')
        expect(html).to include('referrerpolicy="no-referrer"')
        expect(html).to include('decoding="async"')
        expect(html).to include('crossorigin="anonymous"')
        expect(html).not_to include("\n")
      end
    end

    context 'with special characters in title' do
      it 'properly escapes HTML special characters', :aggregate_failures do
        renderer = described_class.new(url: 'https://example.com/image.jpg', title: '<script>alert("xss")</script>')

        expect(renderer.to_html).to include('alt="&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;"')
        expect(renderer.to_html).to include('title="&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;"')
      end
    end

    context 'with special characters in url' do
      it 'properly escapes URL special characters' do
        renderer = described_class.new(url: 'https://example.com/image.jpg?x=1&y=2', title: 'Test')

        expect(renderer.to_html).to include('src="https://example.com/image.jpg?x=1&amp;y=2"')
      end
    end
  end
end
