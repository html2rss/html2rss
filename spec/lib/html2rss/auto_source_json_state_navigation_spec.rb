# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource do
  describe '#articles with Next.js navigation menus in JSON state' do
    subject(:urls) { articles.map { _1.url.to_s } }

    let(:articles) { described_class.new(response, config).articles }

    let(:url) { Html2rss::Url.from_absolute('https://www.example.com/videos/shows/daily-news/') }
    let(:response) do
      Html2rss::RequestService::Response.new(
        body: File.read(File.expand_path('../../fixtures/auto_source/ssr_menu_state_teaser_grid.html', __dir__)),
        headers: { 'content-type' => 'text/html' },
        url:
      )
    end
    let(:teaser_url) { %r{\Ahttps://www\.example\.com/videos/shows/daily-news/[^/]+-\d+\.html\z} }

    context 'with limit 2' do
      let(:config) { described_class::DEFAULT_CONFIG.merge(limit: 2) }

      it 'returns teaser articles instead of menu links', :aggregate_failures do
        expect(urls.size).to eq(2)
        expect(urls).to all(match(teaser_url))
      end
    end

    context 'with the default limit' do
      let(:config) { described_class::DEFAULT_CONFIG }

      it 'admits no navigation or footer menu links', :aggregate_failures do
        expect(urls).not_to be_empty
        expect(urls).to all(match(teaser_url))
      end

      it 'titles no article with the full-episode label' do
        expect(articles.map(&:title)).to all(satisfy { !_1.to_s.include?('Full episode') })
      end
    end
  end
end
