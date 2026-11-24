# frozen_string_literal: true

RSpec.describe Html2rss::Selectors::PostProcessors do
  describe '::NAME_TO_CLASS' do
    specify(:aggregate_failures) do
      expect(described_class::NAME_TO_CLASS).to be_a(Hash)
      expect(described_class::NAME_TO_CLASS).to include(
        :gsub, :markdown_to_html, :parse_time, :parse_uri, :sanitize_html, :substring, :template
      )
    end
  end
end
