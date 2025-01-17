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

  describe '.get_processor' do
    it { expect(described_class.get_processor(:gsub)).to be(Html2rss::Selectors::PostProcessors::Gsub) }

    it {
      expect do
        described_class.get_processor(:html_to_mark)
      end.to raise_error(Html2rss::Selectors::PostProcessors::UnknownPostProcessorName)
    }
  end
end
