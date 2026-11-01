# frozen_string_literal: true

RSpec.describe Html2rss::Html::ArticleRules::Image do
  describe '.largest_from_srcsets' do
    it 'picks the largest width candidate and skips data URLs' do
      srcsets = [
        'data:image/jpeg;base64,abc 100w, https://example.com/a.jpg 200w, https://example.com/b.jpg 800w'
      ]
      expect(described_class.largest_from_srcsets(srcsets)).to eq('https://example.com/b.jpg')
    end

    it 'skips oversized srcset attributes' do
      oversized = "#{'a' * (described_class::MAX_ATTR_CHARS + 1)} 800w"
      expect(described_class.largest_from_srcsets([oversized])).to be_nil
    end

    it 'keeps commas inside URL tokens' do
      srcsets = ['image,with,commas.jpg 256w, another,image,with,commas.jpg 1w']
      expect(described_class.largest_from_srcsets(srcsets)).to eq('image,with,commas.jpg')
    end

    it 'handles candidates joined by comma without spaces' do
      srcsets = ['https://example.com/a.jpg 88w,https://example.com/b.jpg 175w']
      expect(described_class.largest_from_srcsets(srcsets)).to eq('https://example.com/b.jpg')
    end

    it 'tolerates input that ends inside each token kind', :aggregate_failures do
      expect(described_class.largest_from_srcsets(['', ' , ', 'a.jpg', 'a.jpg ', 'a.jpg 100'])).to be_nil
      expect(described_class.largest_from_srcsets(['a.jpg 100w'])).to eq('a.jpg')
      expect(described_class.largest_from_srcsets(['a.jpg 100h'])).to eq('a.jpg')
    end

    it 'skips invalid candidates and continues with the next one', :aggregate_failures do
      expect(described_class.largest_from_srcsets(['junk 12x, ok.jpg 5w'])).to eq('ok.jpg')
      expect(described_class.largest_from_srcsets(['nodescriptor, ok.jpg 5w'])).to eq('ok.jpg')
      expect(described_class.largest_from_srcsets(["a.jpg\t1w,\nb.jpg\r\f2w"])).to eq('b.jpg')
    end

    it 'rejects descriptors without digits or with another unit', :aggregate_failures do
      expect(described_class.largest_from_srcsets(['a.jpg w, b.jpg 2x'])).to be_nil
      expect(described_class.largest_from_srcsets(['a.jpg 0w'])).to eq('a.jpg')
    end

    it 'reads descriptors as decimal and resumes right after the unit', :aggregate_failures do
      expect(described_class.largest_from_srcsets(['a.jpg 010w, b.jpg 9w'])).to eq('a.jpg')
      expect(described_class.largest_from_srcsets(['a.jpg 1w b.jpg 2w'])).to eq('b.jpg')
    end

    it 'keeps multibyte URLs intact with byte-based offsets' do
      srcsets = ['https://example.com/bild-ü.jpg 200w, https://example.com/日本語/ä😀.jpg 800w']
      expect(described_class.largest_from_srcsets(srcsets)).to eq('https://example.com/日本語/ä😀.jpg')
    end

    it 'parses descriptors that follow multibyte URLs' do
      srcsets = ['/é.jpg 900w, /a.jpg 100w']
      expect(described_class.largest_from_srcsets(srcsets)).to eq('/é.jpg')
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

    it 'skips oversized style attributes' do
      oversized = "background: url('#{'x' * (described_class::MAX_ATTR_CHARS + 1)}');"
      expect(described_class.best_from_styles([oversized])).to be_nil
    end
  end
end
