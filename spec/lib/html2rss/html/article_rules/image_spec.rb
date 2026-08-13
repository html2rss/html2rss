# frozen_string_literal: true

RSpec.describe Html2rss::Html::ArticleRules::Image do
  describe '.largest_from_srcsets' do
    it 'picks the largest width candidate and skips data URLs' do
      srcsets = [
        'data:image/jpeg;base64,abc 100w, https://example.com/a.jpg 200w, https://example.com/b.jpg 800w'
      ]
      expect(described_class.largest_from_srcsets(srcsets)).to eq('https://example.com/b.jpg')
    end
  end

  describe '.best_from_styles' do
    it 'returns the longest non-data background url' do # rubocop:disable RSpec/ExampleLength
      styles = [
        'background: url(data:image/png;base64,xx);',
        'background-image: url("short.jpg");',
        "background: url('/path/to/longer-image.jpg');"
      ]
      expect(described_class.best_from_styles(styles)).to eq('/path/to/longer-image.jpg')
    end
  end
end
