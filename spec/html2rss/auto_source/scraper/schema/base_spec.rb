# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::Schema::Base do
  subject(:instance) { described_class.new(schema_object, url: nil) }

  let(:schema_object) do
    { '@type': 'ScholarlyArticle', title: 'Baustellen der Nation' }
  end

  describe '#call' do
    subject(:call) { instance.call }

    it 'sets the title' do
      expect(call).to include(title: 'Baustellen der Nation')
    end
  end
end
