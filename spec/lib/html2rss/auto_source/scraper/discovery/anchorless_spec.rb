# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Discovery::Anchorless do
  describe '.permit_unanchored?' do
    it 'names the SemanticHtml job so fallback_anchorless is not silently class-clustering',
       :aggregate_failures do
      expect(described_class.permit_unanchored?(true)).to be(true)
      expect(described_class.permit_unanchored?(false)).to be(false)
    end
  end

  describe '.class_cluster_containers' do
    let(:parsed_body) { Nokogiri::HTML('<html><body><div class="card">One</div></body></html>') }
    let(:node) { parsed_body.at_css('div') }

    before do
      allow(Html2rss::AutoSource::Scraper::Discovery::ClassClustering)
        .to receive(:call).and_return([node])
    end

    it 'delegates the Html job to ClassClustering rather than Semantic permit rules',
       :aggregate_failures do
      result = described_class.class_cluster_containers(parsed_body, minimum_selector_frequency: 2)

      expect(Html2rss::AutoSource::Scraper::Discovery::ClassClustering)
        .to have_received(:call).with(parsed_body, minimum_selector_frequency: 2)
      expect(result).to eq([node])
    end
  end
end
