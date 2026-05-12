# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::LinkHeuristics do
  subject(:heuristics) { described_class.new('https://example.com/articles/') }

  describe '#destination_facts' do
    it 'returns nil when URL normalization rejects a malformed href' do
      expect(heuristics.destination_facts('http://example .com')).to be_nil
    end

    it 'keeps author routes classified as junk' do
      expect(heuristics.destination_facts('/author/jane'))
        .to have_attributes(high_confidence_junk_path: true, strong_post_suffix: false)
    end

    it 'keeps archive routes classified as junk' do
      expect(heuristics.destination_facts('/archive/2024'))
        .to have_attributes(high_confidence_junk_path: true, content_path: false)
    end

    it 'keeps nested taxonomy routes classified as junk', :aggregate_failures do
      facts = heuristics.destination_facts('/topics/security/cloud-security-updates')

      expect(facts.taxonomy_path).to be(true)
      expect(facts.high_confidence_junk_path).to be(true)
      expect(facts.strong_post_suffix).to be(false)
    end

    it 'does not trust category routes as post context by route alone' do
      expect(heuristics.destination_facts('/category/company/platform-launch-notes-for-teams'))
        .to have_attributes(strong_post_suffix: false, high_confidence_junk_path: true)
    end

    it 'does not trust privacy routes as post context by route alone' do
      expect(heuristics.destination_facts('/privacy/api-announcement-for-enterprise-admins'))
        .to have_attributes(strong_post_suffix: false, high_confidence_junk_path: true)
    end

    it 'recognizes dated news routes as article-like' do
      expect(heuristics.destination_facts('/news/2024/platform-launch-notes'))
        .to have_attributes(content_path: true, strong_post_suffix: true)
    end

    it 'recognizes newsroom routes as article-like' do
      expect(heuristics.destination_facts('/newsroom/2026/platform-launch-notes'))
        .to have_attributes(content_path: true, strong_post_suffix: true)
    end
  end
end
