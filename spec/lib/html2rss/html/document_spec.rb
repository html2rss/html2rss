# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Html::Document do
  describe '.parse' do
    subject(:doc) { described_class.parse('<html><body><!--c--><p id="x">Hi</p></body></html>') }

    it 'returns a facade document', :aggregate_failures do
      expect(doc).to be_a(described_class)
      expect(doc).to be_html_document
      expect(described_class.html_document?(doc)).to be(true)
    end

    it 'supports CSS selection and strips comments', :aggregate_failures do
      expect(doc.at_css('#x').text).to eq('Hi')
      expect(doc.to_html).not_to include('<!--')
    end
  end

  describe '.html_document?' do
    it 'accepts facade and native nokogiri documents', :aggregate_failures do
      expect(described_class.html_document?(described_class.parse('<p>x</p>'))).to be(true)
      expect(described_class.html_document?(Nokogiri::HTML('<p>x</p>'))).to be(true)
      expect(described_class.html_document?({})).to be(false)
    end
  end

  describe '.fragment' do
    it 'parses a fragment via the active backend' do
      fragment = described_class.fragment('<div>Hello</div>')
      expect(fragment.at_css('div').text).to eq('Hello')
    end
  end
end
