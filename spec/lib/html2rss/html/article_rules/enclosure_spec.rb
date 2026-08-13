# frozen_string_literal: true

RSpec.describe Html2rss::Html::ArticleRules::Enclosure do
  let(:base_url) { 'https://example.com' }

  describe '.archive_href?' do
    it { expect(described_class.archive_href?('/a.pdf')).to be(true) }
    it { expect(described_class.archive_href?('/story')).to be(false) }
  end

  describe '.from_image' do
    it 'guesses an image content type', :aggregate_failures do
      result = described_class.from_image('/hero.jpg', base_url)
      expect(result[:url].to_s).to eq('https://example.com/hero.jpg')
      expect(result[:type]).to include('image')
    end
  end

  describe '.from_anchor' do
    it 'types pdf and zip archives', :aggregate_failures do
      pdf = described_class.from_anchor('/doc.pdf', base_url)
      zip = described_class.from_anchor('/bundle.zip', base_url)
      expect(pdf[:type]).to include('pdf').or eq('application/pdf')
      expect(zip[:type]).to eq('application/zip')
    end
  end
end
