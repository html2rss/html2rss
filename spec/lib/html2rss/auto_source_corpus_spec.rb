# frozen_string_literal: true

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

    it 'misses no more enclosures than the recorded baseline', :aggregate_failures do
      rows.each do |row|
        recorded = baseline.dig(row.page, 'enclosure_misses')
        expect(row.enclosure_misses).to be <= recorded,
                                        "#{row.page}: enclosure misses #{row.enclosure_misses} > #{recorded}"
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
end
