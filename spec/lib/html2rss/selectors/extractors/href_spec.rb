# frozen_string_literal: true

require 'nokogiri'

RSpec.describe Html2rss::Selectors::Extractors::Href do
  subject { described_class.new(xml, options).get }

  let(:channel) { { url: 'https://example.com' } }
  let(:options) { instance_double(Struct::HrefOptions, selector: 'a', channel:) }

  context 'with relative href url' do
    let(:xml) { Nokogiri.HTML('<div><a href="/posts/latest-findings">...</a></div>') }

    specify(:aggregate_failures) do
      expect(subject).to be_a(Html2rss::Url)
      expect(subject).to eq Html2rss::Url.from_relative('https://example.com/posts/latest-findings', 'http://example.com')
    end
  end

  context 'with absolute href url' do
    let(:xml) { Nokogiri.HTML('<div><a href="http://example.com/posts/absolute">...</a></div>') }

    specify(:aggregate_failures) do
      expect(subject).to be_a(Html2rss::Url)
      expect(subject).to eq Html2rss::Url.from_relative('http://example.com/posts/absolute', 'http://example.com')
    end
  end
end
