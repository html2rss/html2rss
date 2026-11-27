# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::PageCards do
  [Html2rss::AutoSource::Scraper::Html, Html2rss::AutoSource::Scraper::SemanticHtml].each do |scraper_class|
    describe scraper_class.name do
      let(:slugs) { %w[launch-update api-rollout summer-release] }
      let(:parsed_body) do
        cards = slugs.map do |slug|
          %(<article><h2><a href="/news/#{slug}">Story #{slug} out</a></h2><p>12 March 2024</p></article>)
        end
        Nokogiri::HTML("<html><body><main>#{cards.join}</main></body></html>")
      end

      it 'probes detection against the fixed detection URL', :aggregate_failures do
        allow(scraper_class).to receive(:new).and_call_original

        expect(scraper_class.articles?(parsed_body)).to be(true)
        expect(scraper_class).to have_received(:new)
          .with(parsed_body, url: described_class::DETECTION_BASE_URL, clock: described_class::DETECTION_CLOCK)
        expect(scraper_class.articles?(nil)).to be(false)
      end

      it 'builds its own link resolver and document from the page url when none are provided', :aggregate_failures do
        allow(Html2rss::AutoSource::Scoring::LinkResolver).to receive(:new).and_call_original
        allow(Html2rss::Html::SST::Normalizer).to receive(:call).and_call_original

        expect(scraper_class.new(parsed_body, url: 'https://example.org/', clock: clock_for)).to be_extractable
        expect(Html2rss::AutoSource::Scoring::LinkResolver).to have_received(:new).with('https://example.org/')
        expect(Html2rss::Html::SST::Normalizer).to have_received(:call).with(parsed_body, vocabulary: anything)
      end

      it 'reads a naive leftover date in the given time zone' do # rubocop:disable RSpec/ExampleLength
        cards = slugs.map do |slug|
          %(<article><h2><a href="/news/#{slug}">Story #{slug} out now</a></h2><p>12 March 2024</p></article>)
        end
        dated = Nokogiri::HTML("<html><body><main>#{cards.join}</main></body></html>")
        scraper = scraper_class.new(dated, url: 'https://example.org/', clock: clock_for('Europe/Berlin'))

        expect(scraper.to_a.first.published_at.zone).to eq('+01:00')
      end

      it 'can be built for a url alone' do
        expect { scraper_class.new(url: 'https://example.org/', clock: clock_for) }.not_to raise_error
      end

      it 'reuses a provided document and link resolver', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        resolver = Html2rss::AutoSource::Scoring::LinkResolver.new('https://example.org/')
        document = Html2rss::Html::SST::Normalizer.call(parsed_body, vocabulary: resolver.vocabulary)
        allow(Html2rss::Html::SST::Normalizer).to receive(:call)
        allow(Html2rss::AutoSource::Scoring::LinkResolver).to receive(:new)

        scraper = scraper_class.new(nil, url: 'https://example.org/', document:, link_resolver: resolver,
                                         clock: clock_for)

        expect(scraper).to be_extractable
        expect(Html2rss::Html::SST::Normalizer).not_to have_received(:call)
        expect(Html2rss::AutoSource::Scoring::LinkResolver).not_to have_received(:new)
      end
    end
  end
end
