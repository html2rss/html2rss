# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Html::Backend do
  around do |example|
    described_class.reset!
    example.run
    described_class.reset!
  end

  describe '.resolve' do
    it 'resolves known backends', :aggregate_failures do
      expect(described_class.resolve('nokogiri')).to eq(described_class::Nokogiri)
      expect(described_class.resolve(:nokolexbor)).to eq(described_class::Nokolexbor)
      expect(described_class.resolve(:rust)).to eq(described_class::Rust)
    end

    it 'rejects unknown names' do
      expect { described_class.resolve('libxml') }.to raise_error(ArgumentError, /Unknown HTML backend/)
    end
  end

  describe 'Nokolexbor adapter', :aggregate_failures do
    it 'parses HTML and fragments via Lexbor' do
      skip 'nokolexbor not installed' unless Gem.loaded_specs.key?('nokolexbor') ||
                                            begin
                                              require 'nokolexbor'
                                              true
                                            rescue LoadError
                                              false
                                            end

      described_class.use(:nokolexbor)
      doc = Html2rss::Html::Document.parse('<html><body><!--c--><p id="x">Hi</p></body></html>')
      expect(doc.backend_name).to eq(:nokolexbor)
      expect(doc.at_css('#x').text).to eq('Hi')
      expect(doc.to_html).not_to include('<!--')

      fragment = Html2rss::Html::Document.fragment('<div>Hello</div>')
      expect(fragment.at_css('div').text).to eq('Hello')
    end
  end

  describe 'Rust adapter', :aggregate_failures do
    it 'parses HTML via the native engine' do
      skip 'html2rss_parser not compiled' unless Html2rss::Html::NativeEngine.available?

      described_class.use(:rust)
      doc = Html2rss::Html::Document.parse('<html><body><!--c--><p id="x">Hi</p></body></html>')
      expect(doc.backend_name).to eq(:rust)
      expect(doc.at_css('#x').text).to eq('Hi')
      expect(doc.to_html).not_to include('<!--')

      fragment = Html2rss::Html::Document.fragment('<div>Hello</div>')
      expect(fragment.at_css('div').text).to eq('Hello')
    end
  end
end
