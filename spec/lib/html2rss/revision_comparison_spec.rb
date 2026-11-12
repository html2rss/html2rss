# frozen_string_literal: true

require 'tmpdir'
require_relative '../../support/revision_comparison'
require_relative '../../support/saved_responses'

RSpec.describe RevisionComparison do
  let(:new_run) do
    lambda do |items:, drops: {}, wall_ms: 1.0, error: nil, feed: nil|
      RevisionComparison::Run.new(items:, drops:, wall_ms:, error:, feed:)
    end
  end
  let(:page) { RevisionComparison::Page.new(file: 'list.html', url: 'https://example.com/news/') }

  describe '.parse_manifest' do
    it 'reads tab-separated file and url lines, skipping blanks and comments' do
      text = "# saved pages\n\nlist.html\thttps://example.com/news/\nother.json\thttps://example.com/\n"

      expect(described_class.parse_manifest(text).map(&:to_h)).to eq(
        [{ file: 'list.html', url: 'https://example.com/news/' }, { file: 'other.json', url: 'https://example.com/' }]
      )
    end

    it 'rejects a line without a url' do
      expect { described_class.parse_manifest("list.html\n") }.to raise_error(ArgumentError, /file>\\t<url/)
    end
  end

  describe 'Diff' do
    subject(:diff) { RevisionComparison::Diff.new(page:, base:, head:) }

    let(:base) do
      new_run.call(items: { 'https://example.com/a' => 'Kicker : : A', 'https://example.com/b' => 'B' },
                   drops: { 'junk' => 1, 'menu' => 2 })
    end
    let(:head) do
      new_run.call(items: { 'https://example.com/a' => 'Kicker: A', 'https://example.com/c' => 'C' },
                   drops: { 'junk' => 1, 'sponsored' => 3 })
    end

    it 'lists items only one side admits', :aggregate_failures do
      expect(diff.gained).to eq('https://example.com/c' => 'C')
      expect(diff.lost).to eq('https://example.com/b' => 'B')
    end

    it 'lists title changes for shared items only' do
      expect(diff.title_changes).to eq([['https://example.com/a', 'Kicker : : A', 'Kicker: A']])
    end

    it 'tallies every drop reason on either side' do
      expect(diff.drop_tallies).to eq('junk' => [1, 1], 'menu' => [2, 0], 'sponsored' => [0, 3])
    end
  end

  describe '.report' do
    let(:base) { new_run.call(items: { 'https://example.com/a' => 'Old', 'https://example.com/b' => 'B' }, wall_ms: 10.0) }
    let(:head) { new_run.call(items: { 'https://example.com/a' => 'New' }, drops: { 'sponsored' => 1 }, wall_ms: 8.5) }
    let(:expected) do
      <<~REPORT.chomp
        compare-revisions abc123 -> def456 (1 pages)
        list.html  https://example.com/news/
          items  2 -> 1
          lost   https://example.com/b  "B"
          title  https://example.com/a
                   - "Old"
                   + "New"
          drops  sponsored: 0 -> 1
          wall   10.0ms -> 8.5ms
        TOTAL  items 2 -> 1  lost 1  gained 0  retitled 1  errored 0  wall 10.0ms -> 8.5ms
      REPORT
    end

    it 'prints counts, lost items, title changes, drops and wall time per page' do
      diffs = described_class.diffs([page], [base], [head])

      expect(described_class.report(diffs, %w[abc123 def456])).to eq(expected)
    end

    it 'shows the native feed split where a feed contributed' do
      diffs = described_class.diffs([page], [base.with(feed: [5, 4, nil])], [head.with(feed: [4, 4, 3])])

      expect(described_class.report(diffs, %w[a b]).lines(chomp: true))
        .to include('  feed   feed 5 page 4 merged - -> feed 4 page 4 merged 3')
    end

    it 'reports a run error on its side' do
      report = described_class.report(
        described_class.diffs([page], [base], [base.with(items: {}, error: 'RuntimeError: boom')]), %w[a b]
      )

      expect(report.lines(chomp: true)).to include('  error  head: RuntimeError: boom')
    end

    it 'counts an errored page apart from the lost and gained totals' do
      other = RevisionComparison::Page.new(file: 'other.html', url: 'https://example.com/other/')
      diffs = described_class.diffs([page, other], [base, base], [base.with(items: {}, error: 'boom'), head])

      expect(described_class.report(diffs, %w[a b]).lines(chomp: true).last)
        .to start_with('TOTAL  items 4 -> 1  lost 1  gained 0  retitled 1  errored 1  wall')
    end

    it 'counts a page that errored on the base side as errored' do
      report = described_class.report(
        described_class.diffs([page], [base.with(items: {}, error: 'RuntimeError: boom')], [head]), %w[a b]
      )

      expect(report.lines(chomp: true).last).to include('lost 0  gained 0  retitled 0  errored 1')
    end
  end

  describe '.load_pages' do
    it 'limits the manifest to the first entries' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, described_class::MANIFEST), "a.html\thttps://example.com/\nb.html\thttps://example.com/\n")

        expect(described_class.load_pages(dir, limit: 1).map(&:file)).to eq(['a.html'])
      end
    end
  end

  describe '.measure' do
    it 'splits a feed-backed page into feed, page and merged items' do
      saved = RevisionComparison::Page.new(file: 't6_feed_merge.html', url: AutoSourceCorpus::BASE_URL)
      responses = SavedResponses.new(File.join(AutoSourceCorpus::ROOT, 't6_feed_merge'))
      run = described_class.measure([saved], AutoSourceCorpus::ROOT, responses:).first

      expect(run.feed).to eq([4, 4, 3])
    end

    it 'runs a saved page offline through the shared corpus runner' do
      Dir.mktmpdir do |dir|
        FileUtils.cp(File.join(AutoSourceCorpus::ROOT, 'plain_listing.html'), File.join(dir, 'p.html'))
        saved = RevisionComparison::Page.new(file: 'p.html', url: AutoSourceCorpus::BASE_URL)

        expect(described_class.measure([saved], dir).first.items.size).to eq(6)
      end
    end
  end
end
