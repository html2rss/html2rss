# frozen_string_literal: true

require 'nokogiri'
require 'addressable'

RSpec.describe Html2rss::Selectors::Extractors::Href do
  subject { described_class.new(xml, options).get }

  let(:channel) { { url: 'https://example.com' } }
  let(:options) { instance_double(Struct::HrefOptions, selector: 'a', channel:) }

  context 'with relative href url' do
    let(:xml) { Nokogiri.HTML('<div><a href="/posts/latest-findings">...</a></div>') }

    specify(:aggregate_failures) do
      expect(subject).to be_a(Addressable::URI)
      expect(subject).to eq Addressable::URI.parse('https://example.com/posts/latest-findings')
    end
  end

  context 'with absolute href url' do
    let(:xml) { Nokogiri.HTML('<div><a href="http://example.com/posts/absolute">...</a></div>') }

    specify(:aggregate_failures) do
      expect(subject).to be_a(Addressable::URI)
      expect(subject).to eq Addressable::URI.parse('http://example.com/posts/absolute')
    end
  end
end
