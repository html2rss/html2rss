# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Channel::Metadata do
  describe '#call' do
    subject(:call) { described_class.new(parsed_body, url:).call }

    let(:url) { 'https://example.com' }

    context 'with a title' do
      let(:parsed_body) { Nokogiri::HTML('<html><head><title>Example</title></head></html>') }

      it 'extracts the title' do
        expect(call[:title]).to eq('Example')
      end
    end

    context 'without a title' do
      let(:parsed_body) { Nokogiri::HTML('<html><head></head></html>') }

      it 'extracts nil' do
        expect(call[:title]).to be_nil
      end
    end

    context 'with a language' do
      let(:parsed_body) { Nokogiri::HTML('<!doctype html><html lang="fr"><body></body></html>') }

      it 'extracts the language' do
        expect(call[:language]).to eq('fr')
      end
    end

    context 'without a language' do
      let(:parsed_body) { Nokogiri::HTML('<html></html>') }

      it 'extracts nil' do
        expect(call[:language]).to be_nil
      end
    end

    context 'with a description' do
      let(:parsed_body) do
        Nokogiri::HTML('<head><meta name="description" content="Example"></head>')
      end

      it 'extracts the description' do
        expect(call[:description]).to eq('Example')
      end
    end

    context 'without a description' do
      let(:parsed_body) { Nokogiri::HTML('<head></head>') }

      it 'extracts nil' do
        expect(call[:description]).to be_nil
      end
    end
  end
end
