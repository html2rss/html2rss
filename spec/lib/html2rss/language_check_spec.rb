# frozen_string_literal: true

require 'json'
require 'tmpdir'
require 'fileutils'

# bin/language-check is a script: load it once so its constants are defined once.
load File.expand_path('../../../bin/language-check', __dir__) unless defined?(LanguageCheck)

RSpec.describe LanguageCheck do
  let(:pages_dir) { Dir.mktmpdir('language-check-spec-') }
  let(:pages) do
    files = %w[cta_sentence_links_box.html menu_mixed_top_level.html]
    files.each { FileUtils.cp(File.expand_path("../../fixtures/auto_source/corpus/#{_1}", __dir__), pages_dir) }
    File.write(File.join(pages_dir, 'manifest.tsv'), files.map { "#{_1}\thttps://example.com/news/\n" }.join)
    described_class.validate!(code: 'en', pages: pages_dir)
  end
  let(:head) { described_class.measure(pages, pages_dir, 'en', trace: false, evidence: true) }
  # A base measurement that differs from the head the way a vocabulary change would.
  let(:changed_base) do
    base = JSON.parse(JSON.generate(head))
    first, second = base.fetch('pages').values
    first['items'].shift
    second['items'].reverse!
    second['error'] = 'RuntimeError: boom'
    result = base.fetch('anchors').values.first.values.first
    result[0] = !result[0]
    base
  end
  let(:report_for) do
    lambda do |base|
      meta = { code: 'en', pages:, base_sha: 'a' * 40, head_sha: 'b' * 40, dirty: true }
      described_class::Report.new(meta, { 'measure' => base, 'memory' => [100, 110, 120, 130, 140] },
                                  { 'measure' => head, 'memory' => [150, 160, 170, 180, 190] })
    end
  end

  after { FileUtils.rm_rf(pages_dir) }

  describe 'input validation' do
    it 'rejects a missing or malformed CODE', :aggregate_failures do
      expect do
        described_class.validate!(pages: pages_dir)
      end.to raise_error(described_class::Failure, /CODE is required/)
      expect { described_class.validate!(code: 'x1', pages: pages_dir) }
        .to raise_error(described_class::Failure, /not a language code/)
    end

    it 'rejects a missing PAGES or manifest', :aggregate_failures do
      expect { described_class.validate!(code: 'ru') }.to raise_error(described_class::Failure, /PAGES is required/)
      expect { described_class.validate!(code: 'ru', pages: pages_dir) }
        .to raise_error(described_class::Failure, /has no manifest.tsv/)
    end

    it 'rejects a code the head vocabulary does not know' do
      expect { described_class.language('xx') }.to raise_error(described_class::Failure, /unknown language "xx"/)
    end

    it 'rejects a manifest naming a missing page' do
      File.write(File.join(pages_dir, 'manifest.tsv'), "gone.html\thttps://example.com/\n")

      expect { described_class.validate!(code: 'en', pages: pages_dir) }
        .to raise_error(described_class::Failure, /missing page: gone.html/)
    end
  end

  describe 'the report' do
    it 'finds no change when both trees agree' do
      summary = report_for.call(head).summary('report.md')

      expect(summary).to include('compared 2 of 2 pages, 0 changes', 'anchors: 0 changed of')
    end

    it 'detects removed, reordered, reclassified and one-sided errored pages', :aggregate_failures do
      summary = report_for.call(changed_base).summary('report.md')

      expect(summary).to include('compared 1 of 2 pages', 'errored in one tree 1', 'CHANGE errored in one tree')
      expect(summary).to match(/anchors: 1 changed of \d+ .*utility\? 1/)
    end

    it 'records the revisions and whether the head was dirty', :aggregate_failures do
      full = report_for.call(changed_base).full

      expect(full).to include("base #{'a' * 40}", "head #{'b' * 40}", 'dirty')
      expect(full).to include('added')
    end

    it 'flags a loose label term whose hits are mostly long texts, and path concepts without hits',
       :aggregate_failures do
      summary = report_for.call(head).summary('report.md')

      expect(head.dig('evidence', 'labels').find { _1['term'] == 'contact' }).to include('hits' => 2, 'long' => 2)
      expect(summary).to include('FLAG utility "contact"', 'path concepts with zero hits')
    end

    it 'keeps the terminal summary within 30 lines' do
      expect(report_for.call(changed_base).summary('report.md').lines.size).to be <= 30
    end
  end

  describe 'the command line' do
    it 'defaults BASE and keeps an unset OUT or BASE empty value out of the options', :aggregate_failures do
      options = described_class.parse_options(['--code', 'ru', '--pages', '/pages', '--base', '', '--out', ''])

      expect(options).to eq(base: 'origin/master', code: 'ru', pages: '/pages')
    end

    it 'prints one line and exits 1 on a failure of the tool', :aggregate_failures do
      allow(described_class).to receive(:exit)

      expect { described_class.main(%w[--code x1 --pages /pages]) }
        .to output(/\Alanguage-check: CODE "x1" is not a language code/).to_stderr
      expect(described_class).to have_received(:exit).with(1)
    end
  end

  describe '.site_diff' do
    it 'lists added, removed and changed allocation sites' do
      diff = described_class.site_diff({ 'A a#x' => 1, 'B b#y' => 2, 'C c#z' => 3 },
                                       { 'A a#x' => 1, 'B b#y' => 5, 'D d#w' => 4 })

      expect(diff).to eq(added: { 'D d#w' => 4 }, removed: { 'C c#z' => 3 }, changed: { 'B b#y' => [2, 5] })
    end
  end

  describe '.with_base_worktree' do
    it 'removes its own worktree when the block raises, leaving every other worktree entry', :aggregate_failures do
      list = -> { `git -C #{described_class::REPO_ROOT} worktree list --porcelain`.lines.grep(/\Aworktree /) }
      before = list.call

      expect { described_class.with_base_worktree('HEAD') { raise 'forced' } }.to raise_error('forced')
      expect(list.call).to eq(before)
    end
  end
end
