# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Selectors::Extractors::Href do
  subject { described_class.new(xml, **options).call }

  let(:options) { { selector: 'a', base_url: 'https://example.com' } }

  context 'with relative href url' do
    let(:xml) { Nokogiri.HTML('<div><a href="/posts/latest-findings">...</a></div>') }

    specify(:aggregate_failures) do
      expect(subject).to be_a(Html2rss::Url)
      expect(subject).to eq Html2rss::Url.from_absolute('https://example.com/posts/latest-findings')
    end
  end

  context 'with absolute href url' do
    let(:xml) { Nokogiri.HTML('<div><a href="http://example.com/posts/absolute">...</a></div>') }

    specify(:aggregate_failures) do
      expect(subject).to be_a(Html2rss::Url)
      expect(subject).to eq Html2rss::Url.from_absolute('http://example.com/posts/absolute')
    end
  end

  context 'when no element matches the selector' do
    let(:xml) { Nokogiri.HTML('<div><a href="/posts/latest-findings">...</a></div>') }
    let(:options) { { selector: 'span', base_url: 'https://example.com' } }

    it { is_expected.to eq Html2rss::Url.from_absolute('https://example.com') }
  end

  context 'when the element has no href attribute' do
    let(:xml) { Nokogiri.HTML('<div><a>...</a></div>') }

    it { is_expected.to eq Html2rss::Url.from_absolute('https://example.com') }
  end

  it 'accepts omitted selector and base url' do
    expect { described_class.new(Nokogiri.HTML('<a href="/x">x</a>')) }.not_to raise_error
  end

  describe '.schema_export' do
    it 'exports the href extractor schema', :aggregate_failures do
      expect(described_class.schema_export).to eq(
        type: 'string', const: 'href', title: 'href',
        description: described_class::DESCRIPTION, examples: ['href']
      )
    end
  end
end
