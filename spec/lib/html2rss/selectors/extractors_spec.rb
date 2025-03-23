# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::Extractors do
  describe '.get(attribute_options, xml)' do
    context 'with valid extractor name' do
      it do
        expect(described_class.get({ extractor: 'static' }, nil)).to be_nil
      end
    end
  end
end
