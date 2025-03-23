# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::PostProcessors do
  describe '::NAME_TO_CLASS' do
    specify(:aggregate_failures) do
      expect(described_class::NAME_TO_CLASS).to be_a(Hash)
      expect(described_class::NAME_TO_CLASS).to include(
        :gsub, :html_to_markdown, :markdown_to_html, :parse_time, :parse_uri, :sanitize_html, :substring, :template
      )
    end
  end

  describe '.get' do
    context 'with unknown post processor name' do
      it do
        expect { described_class.get('inexistent', nil, nil) }
          .to raise_error described_class::UnknownPostProcessorName
      end
    end

    context 'with known post processor name' do
      it do
        expect(described_class.get('parse_uri', 'http://example.com/',
                                   { config: { channel: { url: '' } } })).to be_a(String)
      end
    end
  end
end
