# frozen_string_literal: true

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

    it 'builds no SST on pages whose baseline built none', :aggregate_failures do
      rows.each do |row|
        next if baseline.dig(row.page, 'sst_built')

        expect(row.sst_built).to be(false), "#{row.page}: SST built but baseline built none (perf regression)"
      end
    end
  end
end
