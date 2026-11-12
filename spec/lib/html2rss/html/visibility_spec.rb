# frozen_string_literal: true

RSpec.describe Html2rss::Html::Visibility do
  let(:shown) { { style: nil, hidden: false } }

  describe '.unrendered?' do
    it 'reads the hidden attribute, display:none and hiding utility classes', :aggregate_failures do
      expect(described_class.unrendered?([], style: nil, hidden: true)).to be(true)
      expect(described_class.unrendered?([], style: 'color: red; display : none', hidden: false)).to be(true)
      expect(%w[hidden d-none is-hidden hide].map { described_class.unrendered?([_1], **shown) }).to all(be(true))
      expect(described_class.unrendered?(%w[sr-only hidden-xs], style: 'display: block', hidden: false)).to be(false)
      expect(described_class.unrendered?(%w[card hidden], **shown)).to be(true)
    end
  end

  describe '.screen_reader_only?' do
    it 'matches off-screen and visually-hidden classes with their prefixes', :aggregate_failures do
      tokens = %w[sr-only visually-hidden visuallyhidden u-visually-hidden h-offscreen h-offscreen-focusable
                  _screen-reader-only screen-reader-text off-screen card__sr-only element-invisible SR-Only]

      expect(tokens.reject { described_class.screen_reader_only?([_1]) }).to be_empty
    end

    it 'matches when any one class is screen-reader-only' do
      expect(described_class.screen_reader_only?(%w[label sr-only])).to be(true)
    end

    it 'leaves look-alike classes alone' do
      tokens = %w[sr-only-wrapper offscreen-menu-toggle visually reader hidden screenreader-friendly]

      expect(tokens.select { described_class.screen_reader_only?([_1]) }).to be_empty
    end
  end

  describe '.concealed?' do
    it 'is either kind', :aggregate_failures do
      expect(described_class.concealed?(%w[sr-only], **shown)).to be(true)
      expect(described_class.concealed?(%w[d-none], **shown)).to be(true)
      expect(described_class.concealed?(%w[teaser], **shown)).to be(false)
      expect(described_class.concealed?(%w[teaser], style: 'display:none', hidden: false)).to be(true)
      expect(described_class.concealed?(%w[teaser], style: nil, hidden: true)).to be(true)
    end
  end
end
