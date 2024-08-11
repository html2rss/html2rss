# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource do
  subject(:instance) { described_class.new(url) }

  let(:url) { 'https://example.com' }

  describe '#article_extractors' do
    context 'when no article extractors are available' do
      let(:parsed_body) { Nokogiri.HTML('<html><body></body></html>').freeze }

      before do
        allow(instance).to receive(:parsed_body).and_return(parsed_body) # rubocop:disable RSpec/SubjectStub
        allow(instance).to receive(:article_extractors).and_call_original # rubocop:disable RSpec/SubjectStub
      end

      it 'raises NoArticleExtractorFound error' do
        expect { instance.send(:article_extractors) }.to raise_error(Html2rss::AutoSource::NoArticleExtractorFound)
      end
    end
  end
end
