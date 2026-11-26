# frozen_string_literal: true

RSpec.describe Html2rss::Html::SST::Tags::PagerReadings do
  describe '.build' do
    let(:none) { { pager_label: '', page_link: '', page_link_label: '' } }
    let(:own) { { pager_label: 'bladeren-xx', page_link: 'volgende-xx', page_link_label: 'vorige-xx' } }

    it 'reads the shared pager nouns as a word start and page links as shared wording', # rubocop:disable RSpec/ExampleLength
       :aggregate_failures do
      readings = described_class.build(none)

      expect(readings.pager_label.match?('Results pagination')).to be(true)
      expect(readings.pager_label.match?('paginated list')).to be(false)
      expect(readings.pager_label.match?('Bladeren-xx')).to be(false)
      expect(readings.page_link_text.match?('Next page')).to be(true)
      expect(readings.page_link_text.match?('12')).to be(true)
      expect(readings.page_link_text.match?("NEXT page\nof results")).to be(true)
      expect(readings.pager_label.match?('RESULTS PAGINATION')).to be(true)
      expect(readings.page_link_label.match?('Suivant »')).to be(true)
      expect(readings.page_link_label.match?('Suivant le match')).to be(false)
      expect(readings.page_link_label.match?(' ... ')).to be(false)
    end

    it 'reads each own term as a whole label next to the shared ones', # rubocop:disable RSpec/ExampleLength
       :aggregate_failures do
      readings = described_class.build(own)

      expect(readings.pager_label.match?('Results pagination')).to be(true)
      expect(readings.pager_label.match?(' Bladeren-xx ')).to be(true)
      expect(readings.pager_label.match?('Bladeren-xx lijst')).to be(false)
      expect(readings.page_link_label.match?('« Volgende-xx')).to be(true)
      expect(readings.page_link_label.match?('Vorige-xx')).to be(true)
      expect(readings.page_link_label.match?('Suivant »')).to be(true)
      expect(readings.page_link_label.match?('Volgende-xx pagina')).to be(false)
      expect(readings.page_link_text.match?('Volgende-xx')).to be(false)
    end

    it 'shares one entry between every scope without own terms', :aggregate_failures do
      table = described_class::BY_SCOPE

      %i[en ja de all].each { expect(table.fetch(_1)).to be(table.fetch(:en)) }
      expect(table.fetch(:zh)).to be(table.fetch(:en))
    end
  end
end
