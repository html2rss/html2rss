# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../support/auto_source_corpus'

RSpec.describe Html2rss::AutoSource do
  describe 'labeled corpus ratchet' do
    # The corpus run is expensive; compute it once for all examples.
    before(:context) { @rows = AutoSourceCorpus.run } # rubocop:disable RSpec/BeforeAfterAll

    let(:rows) { @rows } # rubocop:disable RSpec/InstanceVariable
    let(:baseline) { AutoSourceCorpus.baseline }
    let(:rerecord) { "re-record with `#{AutoSourceCorpus::RECORD_COMMAND}` when the change is intended" }

    it 'has a recorded baseline for every corpus page' do
      expect(AutoSourceCorpus.pages).to match_array(baseline.keys), rerecord
    end

    it 'admits no more junk than the recorded baseline', :aggregate_failures do
      rows.each do |row|
        recorded = baseline.dig(row.page, 'junk')
        expect(row.junk).to be <= recorded, "#{row.page}: junk #{row.junk} > baseline #{recorded}"
      end
    end

    it 'finds no fewer real items than the recorded baseline', :aggregate_failures do
      rows.each do |row|
        recorded = baseline.dig(row.page, 'real')
        expect(row.real).to be >= recorded, "#{row.page}: real #{row.real} < baseline #{recorded}"
      end
    end

    it 'misses no more exact titles than the recorded baseline', :aggregate_failures do
      rows.each do |row|
        recorded = baseline.dig(row.page, 'title_misses')
        expect(row.title_misses).to be <= recorded, "#{row.page}: title misses #{row.title_misses} > #{recorded}"
      end
    end

    %w[enclosure_misses image_misses].each do |key|
      it "has no more #{key} than the recorded baseline", :aggregate_failures do
        rows.each do |row|
          recorded = baseline.dig(row.page, key)
          expect(row.to_h[key.to_sym]).to be <= recorded, "#{row.page}: #{key} #{row.to_h[key.to_sym]} > #{recorded}"
        end
      end
    end

    it 'builds no SST on pages whose baseline built none', :aggregate_failures do
      rows.each do |row|
        next if baseline.dig(row.page, 'sst_built')

        expect(row.sst_built).to be(false), "#{row.page}: SST built but baseline built none (perf regression)"
      end
    end
  end

  describe 'AutoSourceCorpus.auto_source' do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, 'page.html') }
    let(:links) { (1..6).map { |i| %(<li><a href="/news/story-#{i}">Café über Straße número #{i}</a></li>) } }
    let(:html) do
      %(<!doctype html><html><head><meta charset="iso-8859-15"></head><body><ul>#{links.join}</ul></body></html>)
    end
    let(:titles) { AutoSourceCorpus.auto_source(path:, url: 'https://example.com/news/').articles.map(&:title) }

    before { File.write(path, html, encoding: Encoding::UTF_8) }

    after { FileUtils.remove_entry(dir) }

    it 'decodes a saved UTF-8 page despite a stale non-UTF-8 meta charset' do
      expect(titles).to include('Café über Straße número 1')
    end
  end

  describe 'list-level more labels in a page-only language' do
    let(:dir) { Dir.mktmpdir }
    let(:path) { File.join(dir, 'page.html') }
    let(:pairs) do
      {
        zh: %w[查看全部 查看更多 更多],
        ko: ['더보기'],
        ar: ['المزيد', 'عرض الكل', 'عرض المزيد'],
        fa: ['بیشتر', 'مشاهده بیشتر', 'مشاهده همه'],
        th: %w[ดูเพิ่มเติม ดูเพิ่ม ดูทั้งหมด เพิ่มเติม],
        tr: ['daha fazla', 'daha fazlası', 'daha fazla göster', 'tümünü gör', 'tümünü göster', 'hepsini gör'],
        id: [
          'lihat semua', 'lihat semuanya', 'lihat lainnya', 'lihat lebih banyak', 'lihat berita lainnya',
          'berita lainnya', 'lainnya'
        ],
        vi: ['xem thêm', 'xem tất cả', 'xem toàn bộ'],
        cs: [
          'zobrazit všechny', 'zobrazit vše', 'zobrazit více', 'zobrazit další', 'načíst další', 'načíst více',
          'všechny články', 'všechny zprávy', 'další články', 'další zprávy'
        ],
        hu: [
          'összes', 'összes megtekintése', 'összes hír', 'összes friss hír', 'összes cikk', 'mutasd mindet',
          'még több hír', 'még több cikk', 'további hírek', 'további cikkek', 'további cikkeink', 'további epizódok',
          'további tartalmak', 'tovább a rovatra'
        ],
        ro: [
          'vezi toate', 'vezi toate articolele', 'vezi toate știrile', 'vezi mai multe știri', 'toate articolele',
          'toate știrile', 'citește mai multe știri'
        ],
        da: ['se alle', 'se flere', 'flere nyheder']
      }.flat_map { |code, labels| labels.map { [code, _1] } }
    end
    let(:count) do
      lambda do |code, label, extra|
        cards = (1..6).map do |i|
          %(<article><h2>Real headline #{i} with several words</h2><p>A summary sentence.</p>) +
            %(<a href="/section/long-article-slug-#{i}#{'.html' if i > 3}">#{label}</a></article>)
        end
        File.write(path, %(<!doctype html><html lang="#{code}"><body>#{cards.join}#{extra}</body></html>))
        AutoSourceCorpus.auto_source(path:, url: 'https://example.com/section/').articles.size
      end
    end
    let(:menu_and_footer) do
      lambda do |label|
        %(<div class="menu"><ul><li><a href="/sections">#{label}</a></li></ul></div>) +
          %(<footer><a href="/archive">#{label}</a></footer>)
      end
    end

    after { FileUtils.remove_entry(dir) }

    it 'keeps every card linked by a list-level more label', :aggregate_failures do
      pairs.each { |code, label| expect(count.call(code, label, '')).to eq(6), "#{code} #{label}" }
    end

    it 'adds no item for a menu or footer link with the label', :aggregate_failures do
      pairs.each do |code, label|
        expect(count.call(code, label, menu_and_footer.call(label))).to eq(6), "#{code} #{label}"
      end
    end
  end

  describe '.response' do
    let(:dir) { Dir.mktmpdir('corpus-encoding-') }
    let(:url) { 'https://example.com/news/' }
    let(:page_text) do
      lambda do |html, encoding|
        path = File.join(dir, 'page.html')
        File.binwrite(path, html.encode(encoding))
        AutoSourceCorpus.response(path:, url:).parsed_body.at_css('h1').text
      end
    end

    after { FileUtils.rm_rf(dir) }

    it 'decodes non-UTF-8 pages from their own meta charset', :aggregate_failures do
      { 'windows-1251' => 'Новости дня', 'GBK' => '今日新闻', 'Big5' => '今日新聞' }.each do |charset, text|
        html = "<html><head><meta charset=\"#{charset}\"></head><body><h1>#{text}</h1></body></html>"

        expect(page_text.call(html, charset)).to eq(text)
      end
    end

    it 'keeps a valid UTF-8 page UTF-8 despite a stale meta charset' do
      html = '<html><head><meta charset="windows-1251"></head><body><h1>Новости дня</h1></body></html>'

      expect(page_text.call(html, 'UTF-8')).to eq('Новости дня')
    end

    it 'leaves invalid UTF-8 without a declared charset visibly undecoded' do
      html = '<html><body><h1>Новости дня</h1></body></html>'

      expect(page_text.call(html, 'windows-1251')).to include("\uFFFD")
    end
  end
end
