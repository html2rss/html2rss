# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Config::SelectorsValidator do
  subject(:result) { described_class.call(config) }

  let(:config) do
    {}
  end

  describe 'Items' do
    let(:config) do
      { items: { selector: '.article' } }
    end

    it { is_expected.to be_success }

    context 'with invalid order' do
      let(:config) do
        { items: { selector: 'items', order: 'invalid' } }
      end

      it { expect(result).to be_failure }
    end

    context 'with pagination max_pages' do
      let(:config) do
        { items: { selector: '.article', pagination: { max_pages: 3 } } }
      end

      it { is_expected.to be_success }
    end

    context 'with integer pagination' do
      let(:config) do
        { items: { selector: '.article', pagination: 3 } }
      end

      it { is_expected.to be_success }
    end

    context 'with invalid pagination strategy' do
      let(:config) do
        { items: { selector: '.article', pagination: { strategy: 'invalid_strategy' } } }
      end

      it 'fails with nested path under items', :aggregate_failures do
        expect(result).to be_failure
        expect(result.errors.map(&:path)).to include(%i[items pagination])
      end
    end

    context 'with custom_selector strategy missing selector' do
      let(:config) do
        { items: { selector: '.article', pagination: { strategy: 'custom_selector' } } }
      end

      it 'fails validation', :aggregate_failures do
        expect(result).to be_failure
      end
    end

    context 'with json_cursor strategy missing cursor_path or next_url_path' do
      let(:config) do
        { items: { selector: '.article', pagination: { strategy: 'json_cursor' } } }
      end

      it 'fails validation', :aggregate_failures do
        expect(result).to be_failure
      end
    end

    context 'with invalid pagination max_pages' do
      let(:config) do
        { items: { selector: '.article', pagination: { max_pages: 0 } } }
      end

      it 'fails validation', :aggregate_failures do
        expect(result).to be_failure
      end
    end

    context 'with explicit nil pagination max_pages' do
      let(:config) do
        { items: { selector: '.article', pagination: { max_pages: nil } } }
      end

      # Explicit nil must fail loud: a truthy check would silently accept it and
      # leave runtime paging without a positive Integer budget.
      it 'fails validation', :aggregate_failures do
        expect(result).to be_failure
      end
    end
  end

  describe 'Selector' do
    context 'when contains a selector of type Hash' do
      let(:config) do
        { description: { selector: {} } }
      end

      it { expect(result).to be_failure }
    end

    context 'when does not contain a selector but post_process' do
      let(:config) do
        { description: { post_process: [] } }
      end

      it { is_expected.to be_success }
    end

    context 'when does not contain a selector but static' do
      let(:config) do
        { description: { static: 'foobar' } }
      end

      it { is_expected.to be_success }
    end
  end

  describe 'Selectors: Array Selector' do
    %i[categories guid].each do |array_selector|
      context "when #{array_selector} used symbol keys" do
        let(:config) do
          { array_selector => [:foo], foo: { selector: 'bar' } }
        end

        it { is_expected.to be_success }
      end

      context "when #{array_selector} uses string keys" do
        let(:config) do
          { array_selector => ['foo'], foo: { selector: 'bar' } }
        end

        it { is_expected.to be_success }
      end

      context "when #{array_selector} is not an array" do
        let(:config) do
          { array_selector => {} }
        end

        it { is_expected.to be_failure }
      end

      context "when #{array_selector} is empty" do
        let(:config) do
          { array_selector => %w[] }
        end

        it { is_expected.to be_failure }
      end

      context "when #{array_selector} is references unspecificed" do
        let(:config) do
          { array_selector => %w[bar] }
        end

        it { is_expected.to be_failure }
      end
    end
  end

  describe 'Selectors post_process' do
    context 'with gsub' do
      let(:config) do
        { title: { post_process: [{ name: 'gsub', pattern: 'foo', replacement: 'bar' }] } }
      end

      it { is_expected.to be_success }
    end

    context 'with gsub Hash replacement' do
      let(:config) do
        { title: { post_process: [{ name: 'gsub', pattern: '/[eo]/', replacement: { 'e' => '3' } }] } }
      end

      it { is_expected.to be_success }
    end

    context 'with nested gsub quantifiers' do
      let(:config) do
        { title: { post_process: [{ name: 'gsub', pattern: '(a+)+', replacement: 'x' }] } }
      end

      it 'fails through Gsub compile', :aggregate_failures do
        expect(result).to be_failure
        expect(result.errors.map(&:text)).to include('pattern contains nested quantifiers')
      end
    end

    context 'with overlapping gsub alternation' do
      let(:config) do
        { title: { post_process: [{ name: 'gsub', pattern: '(a|aa)+', replacement: 'x' }] } }
      end

      it { is_expected.to be_success }
    end

    context 'with substring without end' do
      let(:config) do
        { title: { post_process: [{ name: 'substring', start: 0 }] } }
      end

      it { is_expected.to be_success }
    end

    context 'with substring' do
      let(:config) do
        { title: { post_process: [{ name: 'substring', start: 0, end: 1 }] } }
      end

      it { is_expected.to be_success }
    end

    context 'with template' do
      let(:config) do
        { title: { post_process: [{ name: 'template', string: 'foo' }] } }
      end

      it { is_expected.to be_success }
    end

    context 'when post_process name was removed in chore/drop-reverse-markdown' do
      let(:removed_html_to_md_name) { %w[html to markdown].join('_') }

      let(:config) do
        { title: { post_process: [{ name: removed_html_to_md_name }] } }
      end

      it { expect(result).to be_failure }
    end

    context 'with markdown_to_html' do
      let(:config) do
        { title: { post_process: [{ name: 'markdown_to_html' }] } }
      end

      it { is_expected.to be_success }
    end

    context 'with parse_time' do
      let(:config) do
        { title: { post_process: [{ name: 'parse_time' }] } }
      end

      it { is_expected.to be_success }
    end

    context 'with parse_uri' do
      let(:config) do
        { title: { post_process: [{ name: 'parse_uri' }] } }
      end

      it { is_expected.to be_success }
    end

    context 'with sanitize_html' do
      let(:config) do
        { title: { post_process: [{ name: 'sanitize_html' }] } }
      end

      it { is_expected.to be_success }
    end

    context 'with unknown post_processor' do
      let(:config) do
        { title: { post_process: [{ name: 'unknown' }] } }
      end

      it { expect(result).to be_failure }
    end

    context 'with missing post_processor name' do
      let(:config) do
        { title: { post_process: [{}] } }
      end

      it { expect(result).to be_failure }
    end

    context 'without gsub.pattern' do
      let(:config) do
        { title: { post_process: [{ name: 'gsub' }] } }
      end

      it { expect(result).to be_failure }
    end

    context 'without gsub.replacement' do
      let(:config) do
        { title: { post_process: [{ name: 'gsub', pattern: '' }] } }
      end

      it { expect(result).to be_failure }
    end

    context 'without substring.start' do
      let(:config) do
        { title: { post_process: [{ name: 'substring' }] } }
      end

      it { expect(result).to be_failure }
    end

    context 'with invalid substring.end' do
      let(:config) do
        { title: { post_process: [{ name: 'substring', start: 0, end: 'foo' }] } }
      end

      it { expect(result).to be_failure }
    end

    context 'without template.string' do
      let(:config) do
        { title: { post_process: [{ name: 'template' }] } }
      end

      it { expect(result).to be_failure }
    end

    context 'with nil gsub.pattern' do
      let(:config) do
        { title: { post_process: [{ name: 'gsub', pattern: nil, replacement: 'bar' }] } }
      end

      it { expect(result).to be_failure }
    end

    context 'with non-string gsub.pattern' do
      let(:config) do
        { title: { post_process: [{ name: 'gsub', pattern: 1, replacement: 'bar' }] } }
      end

      it { expect(result).to be_failure }
    end

    context 'with non-integer substring.start' do
      let(:config) do
        { title: { post_process: [{ name: 'substring', start: '0' }] } }
      end

      it { expect(result).to be_failure }
    end

    context 'with nil template.string' do
      let(:config) do
        { title: { post_process: [{ name: 'template', string: nil }] } }
      end

      it { expect(result).to be_failure }
    end
  end

  describe 'Selectors :extractor' do
    context 'with attribute' do
      let(:config) do
        { title: { selector: '', extractor: 'attribute', attribute: 'title' } }
      end

      it { is_expected.to be_success }
    end

    context 'with static' do
      let(:config) do
        { title: { extractor: 'static', static: 'foo' } }
      end

      it { is_expected.to be_success }
    end

    context 'with invalid attribute' do
      let(:config) do
        { title: { selector: '', extractor: 'attribute' } }
      end

      it { expect(result).to be_failure }
    end

    context 'with invalid static' do
      let(:config) do
        { title: { selector: '', extractor: 'static' } }
      end

      it { expect(result).to be_failure }
    end

    context 'with unknown extractor' do
      let(:config) do
        { title: { selector: 'h1', extractor: 'nope' } }
      end

      it 'fails with nested path under the selector key', :aggregate_failures do
        expect(result).to be_failure
        expect(result.errors.map(&:path)).to include(%i[title extractor])
      end
    end

    it 'requires OPTIONS members from the extractor registry', :aggregate_failures do
      attribute = described_class.call(title: { selector: 'a', extractor: 'attribute' })
      static = described_class.call(title: { extractor: 'static' })

      expect(attribute).to be_failure
      expect(static).to be_failure
    end
  end

  describe 'Enclosure' do
    specify { expect(described_class::Enclosure).to be < described_class::Selector }

    context 'with selector' do
      let(:config) do
        { enclosure: { selector: 'enclosure' } }
      end

      it { is_expected.to be_success }
    end

    context 'without selector' do
      let(:config) do
        { enclosure: { post_process: [] } }
      end

      it { is_expected.to be_success }
    end

    context 'with invalid content_type' do
      let(:config) do
        { enclosure: { selector: 'enclosure', content_type: 'audio' } }
      end

      it 'fails with nested path under enclosure', :aggregate_failures do
        expect(result).to be_failure
        expect(result.errors.map(&:path)).to include(%i[enclosure content_type])
      end
    end
  end

  describe 'exact issue paths and messages' do
    {
      'items order outside reverse' => [
        { items: { selector: 'x', order: 'bad' } },
        [[%i[items order], 'must be one of: reverse']]
      ],
      'items without selector' => [{ items: { order: 'reverse' } }, [[%i[items selector], 'is missing']]],
      'items enhance as string' => [
        { items: { selector: 'x', enhance: 'yes' } },
        [[%i[items enhance], 'must be boolean']]
      ],
      'items with valid enhance and order' => [{ items: { selector: 'x', order: 'reverse', enhance: true } }, []],
      'pagination integer zero' => [
        { items: { selector: 'x', pagination: 0 } },
        [[%i[items pagination], 'integer must be greater than 0']]
      ],
      'pagination integer negative' => [
        { items: { selector: 'x', pagination: -1 } },
        [[%i[items pagination], 'integer must be greater than 0']]
      ],
      'pagination positive integer' => [{ items: { selector: 'x', pagination: 2 } }, []],
      'pagination string' => [
        { items: { selector: 'x', pagination: 'x' } },
        [[%i[items pagination], 'must be an integer or a hash']]
      ],
      'pagination max_pages string' => [
        { items: { selector: 'x', pagination: { max_pages: 'x' } } },
        [[%i[items pagination], '`max_pages` must be an integer greater than 0']]
      ],
      'pagination max_pages nil' => [
        { items: { selector: 'x', pagination: { max_pages: nil } } },
        [[%i[items pagination], '`max_pages` must be an integer greater than 0']]
      ],
      'pagination max_pages negative' => [
        { items: { selector: 'x', pagination: { max_pages: -1 } } },
        [[%i[items pagination], '`max_pages` must be an integer greater than 0']]
      ],
      'pagination max_pages positive' => [{ items: { selector: 'x', pagination: { max_pages: 3 } } }, []],
      'pagination unknown strategy' => [
        { items: { selector: 'x', pagination: { strategy: 'zz' } } },
        [[%i[items pagination],
          '`strategy` must be one of: rel_next, custom_selector, url_template, offset, json_cursor']]
      ],
      'pagination unknown strategy with string key' => [
        { items: { selector: 'x', pagination: { 'strategy' => 'zz' } } },
        [[%i[items pagination],
          '`strategy` must be one of: rel_next, custom_selector, url_template, offset, json_cursor']]
      ],
      'pagination nil strategy defaults to rel_next' => [
        { items: { selector: 'x', pagination: { strategy: nil } } },
        []
      ],
      'custom_selector without selector' => [
        { items: { selector: 'x', pagination: { strategy: 'custom_selector' } } },
        [[%i[items pagination], '`custom_selector` strategy requires `selector` to be specified']]
      ],
      'custom_selector with blank selector' => [
        { items: { selector: 'x', pagination: { strategy: 'custom_selector', selector: ' ' } } },
        [[%i[items pagination], '`custom_selector` strategy requires `selector` to be specified']]
      ],
      'custom_selector with selector' => [
        { items: { selector: 'x', pagination: { strategy: 'custom_selector', selector: 'a' } } },
        []
      ],
      'json_cursor without cursor fields' => [
        { items: { selector: 'x', pagination: { strategy: 'json_cursor' } } },
        [[%i[items pagination], '`json_cursor` strategy requires either `cursor_path` or `next_url_path`']]
      ],
      'json_cursor with blank cursor fields' => [
        { items: { selector: 'x', pagination: { strategy: 'json_cursor', cursor_path: ' ', next_url_path: '' } } },
        [[%i[items pagination], '`json_cursor` strategy requires either `cursor_path` or `next_url_path`']]
      ],
      'json_cursor with next_url_path' => [
        { items: { selector: 'x', pagination: { strategy: 'json_cursor', next_url_path: 'a' } } },
        []
      ],
      'selector as hash' => [{ title: { selector: {} } }, [[%i[title selector], '`selector` must be a string']]],
      'blank selector string' => [{ title: { selector: '' } }, []],
      'unknown extractor' => [
        { title: { selector: 'h1', extractor: 'nope' } },
        [[%i[title extractor], 'unknown extractor: nope']]
      ],
      'attribute extractor without attribute' => [
        { title: { selector: '', extractor: 'attribute' } },
        [[%i[title attribute], '`attribute` is required for extractor `attribute`']]
      ],
      'static extractor without static' => [
        { title: { extractor: 'static' } },
        [[%i[title static], '`static` is required for extractor `static`']]
      ],
      'post_process entry without name' => [
        { title: { post_process: [{}] } },
        [[%i[title post_process], 'Missing post_processor `name`']]
      ],
      'post_process with nil name' => [
        { title: { post_process: [{ name: nil }] } },
        [[%i[title post_process], 'Missing post_processor `name`']]
      ],
      'post_process unknown name' => [
        { title: { post_process: [{ name: 'unknown' }] } },
        [[%i[title post_process], 'Unknown post_processor `name`: unknown']]
      ],
      'post_process not an array' => [{ title: { post_process: 'x' } }, [[%i[title post_process], 'must be an array']]],
      'post_process entry not a hash' => [
        { title: { post_process: ['x'] } },
        [[[:title, :post_process, 0], 'must be a hash']]
      ],
      'gsub nil pattern' => [
        { title: { post_process: [{ name: 'gsub', pattern: nil, replacement: 'b' }] } },
        [[%i[title pattern], '`pattern` must be a string']]
      ],
      'gsub integer pattern' => [
        { title: { post_process: [{ name: 'gsub', pattern: 1, replacement: 'b' }] } },
        [[%i[title pattern], '`pattern` must be a string']]
      ],
      'gsub invalid regexp' => [
        { title: { post_process: [{ name: 'gsub', pattern: '[', replacement: 'b' }] } },
        [[%i[title pattern], 'Premature end of pattern at [']]
      ],
      'gsub nested quantifiers' => [
        { title: { post_process: [{ name: 'gsub', pattern: '(a+)+', replacement: 'x' }] } },
        [[%i[title pattern], 'pattern contains nested quantifiers']]
      ],
      'gsub without replacement' => [
        { title: { post_process: [{ name: 'gsub', pattern: 'a' }] } },
        [[%i[title replacement], '`replacement` must be a string or a hash']]
      ],
      'gsub empty pattern' => [{ title: { post_process: [{ name: 'gsub', pattern: '', replacement: 'b' }] } }, []],
      'non-gsub post_process with invalid regexp text' => [
        { title: { post_process: [{ name: 'substring', start: 0, pattern: '[' }] } },
        []
      ],
      'substring start as string' => [
        { title: { post_process: [{ name: 'substring', start: '0' }] } },
        [[%i[title start], '`start` must be an integer']]
      ],
      'substring without start' => [
        { title: { post_process: [{ name: 'substring' }] } },
        [[%i[title start], '`start` must be an integer']]
      ],
      'substring end as string' => [
        { title: { post_process: [{ name: 'substring', start: 0, end: 'foo' }] } },
        [[%i[title end], '`end` must be an integer or omitted']]
      ],
      'substring with integer end' => [{ title: { post_process: [{ name: 'substring', start: 0, end: 1 }] } }, []],
      'template without string' => [
        { title: { post_process: [{ name: 'template' }] } },
        [[%i[title string], '`string` must be a string']]
      ],
      'enclosure content_type without subtype' => [
        { enclosure: { selector: 'e', content_type: 'audio' } },
        [[%i[enclosure content_type], 'is in invalid format']]
      ],
      'enclosure content_type audio/mp4' => [{ enclosure: { selector: 'e', content_type: 'audio/mp4' } }, []],
      'guid not an array' => [{ guid: 'x' }, [[%i[guid], '`guid` must be an array']]],
      'guid empty' => [{ guid: [] }, [[%i[guid], '`guid` must contain at least one element']]],
      'guid references unspecified selector' => [
        { guid: ['bar'] },
        [[%i[guid], '`guid` references unspecified `bar`']]
      ],
      'guid with non-name element' => [
        { guid: [1], foo: { selector: 'x' } },
        [[%i[guid], '`guid` must contain only selector names']]
      ],
      'guid with symbol reference' => [{ guid: [:foo], foo: { selector: 'x' } }, []],
      'non-hash config is not an error' => [[], []],
      'categories as a string' => [{ categories: 'x' }, [[%i[categories], '`categories` must be an array']]],
      'categories references unspecified selector' => [
        { categories: ['bar'] },
        [[%i[categories], '`categories` references unspecified `bar`']]
      ],
      'guid with one non-name element among names' => [
        { guid: ['foo', 1], foo: { selector: 'x' } },
        [[%i[guid], '`guid` must contain only selector names']]
      ],
      'guid string reference resolved by string key' => [{ guid: ['foo'], 'foo' => { selector: 'x' } }, []],
      'guid reports every unspecified reference' => [
        { guid: %w[bar baz] },
        [[%i[guid], '`guid` references unspecified `bar`'], [%i[guid], '`guid` references unspecified `baz`']]
      ],
      'guid symbol reference resolved by string key' => [{ guid: [:foo], 'foo' => { selector: 'x' } }, []],
      'string-keyed categories is validated as an array selector' => [
        { 'categories' => 'x' },
        [[['categories'], '`categories` must be an array']]
      ],
      'custom_selector with empty selector' => [
        { items: { selector: 'x', pagination: { strategy: 'custom_selector', selector: '' } } },
        [[%i[items pagination], '`custom_selector` strategy requires `selector` to be specified']]
      ],
      'json_cursor with whitespace-only next_url_path' => [
        { items: { selector: 'x', pagination: { strategy: 'json_cursor', next_url_path: ' ' } } },
        [[%i[items pagination], '`json_cursor` strategy requires either `cursor_path` or `next_url_path`']]
      ],
      'json_cursor with whitespace-only cursor_path' => [
        { items: { selector: 'x', pagination: { strategy: 'json_cursor', cursor_path: ' ' } } },
        [[%i[items pagination], '`json_cursor` strategy requires either `cursor_path` or `next_url_path`']]
      ],
      'json_cursor with only cursor_path' => [
        { items: { selector: 'x', pagination: { strategy: 'json_cursor', cursor_path: 'a' } } },
        []
      ],
      'json_cursor with blank cursor_path and next_url_path' => [
        { items: { selector: 'x', pagination: { strategy: 'json_cursor', cursor_path: ' ', next_url_path: 'a' } } },
        []
      ],
      'json_cursor with blank next_url_path only' => [
        { items: { selector: 'x', pagination: { strategy: 'json_cursor', cursor_path: 'a', next_url_path: ' ' } } },
        []
      ],
      'pagination offset without extra fields' => [
        { items: { selector: 'x', pagination: { strategy: 'offset' } } },
        []
      ],
      'pagination explicit rel_next' => [{ items: { selector: 'x', pagination: { strategy: 'rel_next' } } }, []],
      'pagination zero max_pages with unknown strategy reports both' => [
        { items: { selector: 'x', pagination: { max_pages: 0, strategy: 'zz' } } },
        [[%i[items pagination], '`max_pages` must be an integer greater than 0'],
         [%i[items pagination],
          '`strategy` must be one of: rel_next, custom_selector, url_template, offset, json_cursor']]
      ],
      'non-gsub post_process ignores pattern' => [
        { title: { post_process: [{ name: 'substring', start: 0, pattern: 1 }] } },
        []
      ]

    }.each do |label, (config, expected)|
      it "reports #{label}" do
        expect(described_class.call(config).errors.map { [_1.path, _1.text] }).to eq(expected)
      end
    end

    it 'exposes failure? as the inverse of success?', :aggregate_failures do
      expect(described_class.call(items: { order: 'reverse' }).failure?).to be(true)
      expect(described_class.call(items: { selector: 'x' }).failure?).to be(false)
    end
  end

  describe 'ValidationReport path preservation' do
    # rubocop:disable-next RSpec/ExampleLength
    it 'keeps nested leaf paths through Config.validate', :aggregate_failures do
      values = {
        channel: { url: 'https://example.com' },
        selectors: { items: { selector: '.a', pagination: { strategy: 'invalid_strategy' } } }
      }
      report = Html2rss::Config.validate(values)

      expect(report).to be_failure
      expect(report.issues.map(&:path)).to include(%i[selectors items pagination])
      expect(report.issues.map(&:message).join).to include('strategy')
    end

    # rubocop:disable-next RSpec/ExampleLength
    it 'keeps dynamic selector leaf paths for unknown extractors', :aggregate_failures do
      values = {
        channel: { url: 'https://example.com' },
        selectors: { items: { selector: '.a' }, title: { selector: 'h1', extractor: 'nope' } }
      }
      report = Html2rss::Config.validate(values)

      expect(report).to be_failure
      expect(report.issues.map(&:path)).to include(%i[selectors title extractor])
    end
  end
end
