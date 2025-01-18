# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::ObjectToXmlConverter do
  describe '.call' do
    context 'with object being an object' do
      let(:object) { { 'data' => [{ 'title' => 'Headline', 'url' => 'https://example.com' }] } }
      let(:xml) do
        '<object><data><array><object><title>Headline</title><url>https://example.com</url></object></array></data></object>'
      end

      it 'converts the hash to xml' do
        expect(described_class.new(object).call).to eq xml
      end
    end

    context 'with object being an array' do
      let(:object) { [{ 'title' => 'Headline', 'url' => 'https://example.com' }] }
      let(:xml) do
        '<array><object><title>Headline</title><url>https://example.com</url></object></array>'
      end

      it 'converts the hash to xml' do
        expect(described_class.new(object).call).to eq xml
      end
    end
  end
end
