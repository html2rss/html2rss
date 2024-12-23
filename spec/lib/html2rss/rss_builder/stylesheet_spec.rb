# frozen_string_literal: true

RSpec.describe Html2rss::RssBuilder::Stylesheet do
  let(:rss_maker) { RSS::Maker::RSS20.new }
  let(:stylesheet_config) do
    described_class.new(
      href: 'http://example.com/style.css',
      type: 'text/css',
      media: 'all'
    )
  end

  describe '.add' do
    it 'adds stylesheet XML tags to the RSS maker' do
      expect do
        described_class.add(rss_maker, [stylesheet_config])
      end.to change { rss_maker.xml_stylesheets.size }.by(1)
    end
  end

  describe '#initialize' do
    context 'with valid parameters' do
      it 'creates a Stylesheet object', :aggregate_failures do
        stylesheet = described_class.new(href: 'http://example.com/style.css', type: 'text/css')

        expect(stylesheet.href).to eq('http://example.com/style.css')
        expect(stylesheet.type).to eq('text/css')
        expect(stylesheet.media).to eq('all')
      end
    end

    context 'with an invalid href' do
      it 'raises an ArgumentError' do
        expect do
          described_class.new(href: 123, type: 'text/css')
        end.to raise_error(ArgumentError, 'stylesheet.href must be a String')
      end
    end

    context 'with an invalid type' do
      it 'raises an ArgumentError' do
        expect do
          described_class.new(href: 'http://example.com/style.css', type: 'invalid/type')
        end.to raise_error(ArgumentError, 'stylesheet.type invalid')
      end
    end

    context 'with an invalid media' do
      it 'raises an ArgumentError' do
        expect do
          described_class.new(href: 'http://example.com/style.css', type: 'text/css', media: 123)
        end.to raise_error(ArgumentError, 'stylesheet.media must be a String')
      end
    end
  end

  describe '#to_xml' do
    it 'returns the correct XML string' do
      stylesheet = described_class.new(href: 'http://example.com/style.css', type: 'text/css')
      expected_xml = <<~XML
        <?xml-stylesheet href="http://example.com/style.css" type="text/css" media="all"?>
      XML

      expect(stylesheet.to_xml).to eq(expected_xml)
    end

    context 'with a different media' do
      it 'returns the correct XML string with the specified media' do
        stylesheet = described_class.new(href: 'http://example.com/style.css', type: 'text/css', media: 'screen')
        expected_xml = <<~XML
          <?xml-stylesheet href="http://example.com/style.css" type="text/css" media="screen"?>
        XML

        expect(stylesheet.to_xml).to eq(expected_xml)
      end
    end
  end
end
