# frozen_string_literal: true

RSpec.describe Html2rss::Html::ArticleRules::Image do
  describe '.largest_from_srcsets' do
    it 'picks the largest width candidate and skips data URLs' do
      srcsets = [
        'data:image/jpeg;base64,abc 100w, https://example.com/a.jpg 200w, https://example.com/b.jpg 800w'
      ]
      expect(described_class.largest_from_srcsets(srcsets)).to eq('https://example.com/b.jpg')
    end

    it 'keeps commas inside URL tokens when a width descriptor follows' do
      srcsets = ['image,with,commas.jpg 256w, another,image,with,commas.jpg 1w']
      expect(described_class.largest_from_srcsets(srcsets)).to eq('image,with,commas.jpg')
    end

    it 'handles candidates separated only by commas' do
      srcsets = ['https://example.com/image.88w.jpg 88w,https://example.com/image.175w.jpg 175w']
      expect(described_class.largest_from_srcsets(srcsets)).to eq('https://example.com/image.175w.jpg')
    end

    it 'returns nil for hostile non-srcset input without hanging' do
      expect(described_class.largest_from_srcsets(['!' * 20_000])).to be_nil
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

    it 'supports unquoted and quoted url() forms', :aggregate_failures do
      expect(described_class.best_from_styles(['background: url(image.jpg);'])).to eq('image.jpg')
      expect(described_class.best_from_styles(['background-image: url("image.jpg");'])).to eq('image.jpg')
      expect(described_class.best_from_styles(["background: url('image.jpg');"])).to eq('image.jpg')
    end

    it 'returns nil for hostile incomplete url() input without hanging' do
      expect(described_class.best_from_styles(["url(#{'url(a' * 5_000}"])).to be_nil
    end
  end
end
