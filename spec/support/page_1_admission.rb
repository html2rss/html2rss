# frozen_string_literal: true

module Html2rss
  module SpecSupport
    # Admission counts used by the rust↔nokogiri page_1 characterization lock.
    module Page1Admission
      module_function

      # @param backend [Symbol]
      # @param html [String]
      # @param url [String]
      # @return [Array(Integer, Integer, Integer)] semantic, html scraper, AutoSource sizes
      def counts(backend, html:, url:) # rubocop:disable Metrics/MethodLength
        Html2rss::Html::Backend.use(backend)
        Html2rss::Html::NativeEngine.load! if backend == :rust
        doc = Html2rss::Html::Document.parse(html)
        semantic = Html2rss::AutoSource::Scraper::SemanticHtml.new(
          doc, url:, fallback_anchorless: true
        ).to_a.size
        html_n = Html2rss::AutoSource::Scraper::Html.new(
          doc, url:, fallback_anchorless: true,
               minimum_selector_frequency: 2, use_top_selectors: 5
        ).to_a.size
        response = Html2rss::RequestService::Response.new(
          body: html, headers: { 'content-type' => 'text/html' },
          url: Html2rss::Url.from_absolute(url)
        )
        response.instance_variable_set(:@parsed_body, doc)
        auto = Html2rss::AutoSource.new(response).articles.size
        [semantic, html_n, auto]
      end
    end
  end
end
