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

  describe 'list-level and read-more labels in a page-only language' do # rubocop:disable RSpec/MultipleMemoizedHelpers
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
    let(:true_pairs) do
      {
        vi: 'đọc tiếp', zh: '阅读全文', tr: 'devamını oku', cs: 'číst dále', hu: 'tovább', ro: 'citește mai mult',
        da: 'læs mere', he: 'קראו עוד', el: 'διαβάστε περισσότερα', uk: 'читати далі', hi: 'और पढ़ें'
      }
    end
    let(:urls) do
      lambda do |code, body|
        File.write(path, %(<!doctype html><html lang="#{code}"><body>#{body}</body></html>))
        AutoSourceCorpus.auto_source(path:, url: 'https://example.com/section/').articles.map { _1.url.to_s }
      end
    end
    let(:pages) do
      story = ->(i) { %(<a href="/section/real-story-slug-#{i}">Open this story right now please</a>) }
      cards = lambda { |&block|
        (1..6).map do |i|
          %(<article><h2>Real headline #{i} with several words</h2>#{block.call(i)}</article>)
        end.join
      }
      {
        card_only: lambda { |label|
          cards.call do |i|
            %(<p>A summary.</p><a href="/section/long-slug-#{i}#{'.html' if i > 3}">#{label}</a>)
          end
        },
        menu_footer: lambda { |label|
          cards.call { |i| %(<a href="/section/long-slug-#{i}">#{label}</a>) } +
            %(<div class="menu"><ul><li><a href="/sections">#{label}</a></li></ul></div>) +
            %(<footer><a href="/archive">#{label}</a></footer>)
        },
        hub_and_story: lambda { |label, hub|
          cards.call do |i|
            %(<a href="#{hub}">#{label}</a>#{story.call(i)})
          end
        },
        image_story: lambda { |label|
          (1..6).map do |i|
            %(<article><a href="/section/real-story-slug-#{i}"><img src="/i#{i}.jpg" alt=""></a>) +
              %(<h2>Real headline #{i} with several words</h2><a href="/sports">#{label}</a></article>)
          end.join
        },
        block: lambda { |label, hub, cards|
          intro = %(<div class="block"><h2>Section heading for sports here</h2><p>Latest stories from this section.</p>)
          %(#{intro}<a href="#{hub}">#{label}</a></div>#{cards})
        },
        query_id: lambda { |label, path|
          (1..6).map do |i|
            %(<article><h3>Unlinked title with more words</h3><p>text</p><a href="#{path}#{i}">#{label}</a></article>)
          end.join
        },
        story_label: lambda { |label, destination|
          later = '<a href="/politics/local-news">Local news</a><a href="/world">World</a>' \
                  '<a href="https://source.example.org/wire/item">Wire service</a>'
          (1..6).map do |i|
            %(<article><h3>Council approves the new city budget after long debate #{i}</h3>) +
              %(<a href="#{destination.call(i)}">#{label}</a><a href="/people/jane-doe-#{i}">Jane Doe</a>) +
              %(#{later}</article>)
          end.join
        },
        head: lambda { |label, hub, cards|
          %(<div class="head"><h2>Latest world news today here</h2><a href="#{hub}">#{label}</a></div>) + cards
        }
      }
    end
    let(:layouts) do
      linked = ->(i) { %(<a href="/section/real-story-slug-#{i}">Real headline #{i} with several words</a>) }
      {
        bare: (1..6).map { |i| %(<h2>#{linked.call(i)}</h2>) }.join,
        images: (1..6).map do |i|
          %(<article><a href="/section/real-story-slug-#{i}"><img src="/i#{i}.jpg" alt=""></a>) +
            %(<h2>#{linked.call(i)}</h2></article>)
        end.join
      }
    end

    after { FileUtils.remove_entry(dir) }

    it 'keeps every card linked by a list-level more label', :aggregate_failures do
      pairs.each do |code, label|
        expect(urls.call(code, pages[:card_only].call(label)).size).to eq(6), "#{code} #{label}"
      end
    end

    it 'adds no item for a menu or footer link with the label', :aggregate_failures do
      pairs.each do |code, label|
        expect(urls.call(code, pages[:menu_footer].call(label)).size).to eq(6), "#{code} #{label}"
      end
    end

    it 'keeps the story link of a card, never a hub labelled with the term', :aggregate_failures do
      pairs.uniq(&:first).product(%w[/sports /tin-tuc/the-thao]).each do |(code, label), hub|
        found = urls.call(code, pages[:hub_and_story].call(label, hub))
        expect(found.grep(/real-story-slug/).size).to eq(6), "#{code} #{label} #{hub}"
      end
    end

    it 'ranks a true read-more label as before, whatever it points at and whatever links follow',
       :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      destinations = [->(i) { "/world/council-approves-budget-#{i}" }, ->(i) { "/tin-tuc/budget-#{i}.html" },
                      ->(i) { "/world/48213#{i}" }, ->(i) { "/read?id=#{i}" }]
      true_pairs.to_a.product(destinations).each do |(code, label), destination|
        found = urls.call(code, pages[:story_label].call(label, destination))
        expect(found.size).to eq(6), "#{code} #{label} #{destination.call(1)}"
        expect(found.map { _1.sub('https://example.com', '') }).to eq((1..6).map(&destination)), "#{code} #{label}"
      end
    end

    it 'keeps a card whose only link carries the label and an identifying query', :aggregate_failures do
      pairs.uniq(&:first).product(%w[/read?id= /view?id= /detail?id= /show?aid=]).each do |(code, label), path|
        expect(urls.call(code, pages[:query_id].call(label, path)).size).to eq(6), "#{code} #{path}"
      end
    end

    it 'produces no item on a hub when the card story link is only an image', :aggregate_failures do
      pairs.uniq(&:first).each do |code, label|
        expect(urls.call(code, pages[:image_story].call(label)).grep(/sports/)).to be_empty, "#{code} #{label}"
      end
    end

    it 'adds no item for a section block or heading linked by the term, with or without a query',
       :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      queries = ['', '?page=2', '?sort=new', '?lang=vi', '?utm_source=x']
      pairs.uniq(&:first).product(%i[block head], queries, %i[bare images]).each do |(code, label), kind, query, layout|
        hub = "#{kind == :block ? '/sports' : '/world'}#{query}"
        found = urls.call(code, pages[kind].call(label, hub, layouts.fetch(layout)))
        expect(found.size).to eq(6), "#{code} #{label} #{kind} #{hub} #{layout}"
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
