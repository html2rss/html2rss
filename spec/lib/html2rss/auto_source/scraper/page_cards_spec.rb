# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::PageCards do
  [Html2rss::AutoSource::Scraper::Html, Html2rss::AutoSource::Scraper::SemanticHtml].each do |scraper_class|
    describe scraper_class.name do
      let(:slugs) { %w[launch-update api-rollout summer-release] }
      let(:parsed_body) do
        cards = slugs.map do |slug|
          %(<article><h2><a href="/news/#{slug}">Big #{slug.tr('-', ' ')} announced today</a></h2></article>)
        end
        Nokogiri::HTML("<html><body><main>#{cards.join}</main></body></html>")
      end

      it 'probes detection against the fixed detection URL', :aggregate_failures do
        allow(scraper_class).to receive(:new).and_call_original

        expect(scraper_class.articles?(parsed_body)).to be(true)
        expect(scraper_class).to have_received(:new).with(parsed_body, url: described_class::DETECTION_BASE_URL)
        expect(scraper_class.articles?(nil)).to be(false)
      end

      it 'builds its own link resolver and document from the page url when none are provided', :aggregate_failures do
        allow(Html2rss::Scoring::LinkResolver).to receive(:new).and_call_original
        allow(Html2rss::SST::Normalizer).to receive(:call).and_call_original

        expect(scraper_class.new(parsed_body, url: 'https://example.org/')).to be_extractable
        expect(Html2rss::Scoring::LinkResolver).to have_received(:new).with('https://example.org/')
        expect(Html2rss::SST::Normalizer).to have_received(:call).with(parsed_body, vocabulary: anything)
      end

      it 'can be built for a url alone' do
        expect { scraper_class.new(url: 'https://example.org/') }.not_to raise_error
      end

      it 'reuses a provided document and link resolver', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        resolver = Html2rss::Scoring::LinkResolver.new('https://example.org/')
        document = Html2rss::SST::Normalizer.call(parsed_body, vocabulary: resolver.vocabulary)
        allow(Html2rss::SST::Normalizer).to receive(:call)
        allow(Html2rss::Scoring::LinkResolver).to receive(:new)

        scraper = scraper_class.new(nil, url: 'https://example.org/', document:, link_resolver: resolver)

        expect(scraper).to be_extractable
        expect(Html2rss::SST::Normalizer).not_to have_received(:call)
        expect(Html2rss::Scoring::LinkResolver).not_to have_received(:new)
      end
    end
  end
end
