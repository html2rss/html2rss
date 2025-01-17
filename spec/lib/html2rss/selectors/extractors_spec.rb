# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors do
  describe '.item_extractor_factory(attribute_options, xml)' do
    context 'with unknown extractor name' do
      it do
        expect { described_class.item_extractor_factory({ extractor: 'inexistent' }, nil) }
          .to raise_error described_class::UnknownExtractorName
      end
    end
  end
end
