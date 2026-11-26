# frozen_string_literal: true

RSpec.describe Html2rss::FeedBuilder::Rendering::Media do
  describe '.image' do
    it 'renders the exact img tag', :aggregate_failures do
      html = described_class.image(url: 'https://example.com/i.jpg', title: 'Title')

      expect(html).to eq('<img src="https://example.com/i.jpg" alt="Title" title="Title" loading="lazy" ' \
                         'referrerpolicy="no-referrer" decoding="async" crossorigin="anonymous">')
      expect(html).not_to include("\n")
    end

    it 'escapes the url and the title', :aggregate_failures do
      html = described_class.image(url: 'https://example.com/i.jpg?x=1&y=2', title: '<b>"A" & B</b>')

      expect(html).to include('src="https://example.com/i.jpg?x=1&amp;y=2"')
      escaped = '&lt;b&gt;&quot;A&quot; &amp; B&lt;/b&gt;'
      expect(html).to include(%(alt="#{escaped}" title="#{escaped}"))
    end

    it 'renders a Url value as its string' do
      html = described_class.image(url: Html2rss::Url.from_absolute('https://example.com/i.jpg'), title: 'T')

      expect(html).to include('src="https://example.com/i.jpg"')
    end

    it 'renders empty alt and title for a nil or empty title', :aggregate_failures do
      [nil, ''].each do |title|
        expect(described_class.image(url: 'https://example.com/i.jpg', title:)).to include('alt="" title=""')
      end
    end
  end

  describe '.player' do
    it 'renders the exact audio element with escaped attributes' do
      html = described_class.player(:audio, url: 'https://example.com/a.mp3?x=1&y=2', type: 'audio/"mpeg"')

      expect(html).to eq('<audio controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous">' \
                         '<source src="https://example.com/a.mp3?x=1&amp;y=2" type="audio/&quot;mpeg&quot;"></audio>')
    end

    it 'renders a Url value as its string' do
      url = Html2rss::Url.from_absolute('https://example.com/v.mp4')

      expect(described_class.player(:video, url:, type: 'video/mp4')).to include('src="https://example.com/v.mp4"')
    end

    it 'renders an empty type for a missing MIME type' do
      html = described_class.player(:audio, url: 'https://example.com/a.mp3', type: nil)

      expect(html).to include('type=""')
    end

    it 'renders the exact video element with escaped attributes' do
      html = described_class.player(:video, url: 'https://example.com/v.mp4?x=1&y=2', type: 'video/mp4')

      expect(html).to eq('<video controls preload="none" referrerpolicy="no-referrer" crossorigin="anonymous" ' \
                         'playsinline><source src="https://example.com/v.mp4?x=1&amp;y=2" type="video/mp4"></video>')
    end
  end
end
