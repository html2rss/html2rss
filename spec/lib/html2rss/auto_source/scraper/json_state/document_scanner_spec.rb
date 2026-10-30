# frozen_string_literal: true

RSpec.describe Html2rss::AutoSource::Scraper::JsonState::DocumentScanner do
  describe '.json_documents' do
    it 'combines JSON script payloads with global assignment payloads', :aggregate_failures do
      doc = Nokogiri::HTML(<<~HTML)
        <script type="application/json">{"a":1}</script>
        <script>window.STATE = {"b":2};</script>
      HTML

      expect(described_class.json_documents(doc)).to eq([{ a: 1 }, { b: 2 }])
    end
  end

  describe '.script_documents' do
    it 'parses only application/json scripts' do
      doc = Nokogiri::HTML('<script type="application/json">{"a":1}</script><script>{"c":3}</script>')

      expect(described_class.script_documents(doc)).to eq([{ a: 1 }])
    end

    it 'skips unparseable application/json payloads' do
      doc = Nokogiri::HTML('<script type="application/json">{broken</script>')

      expect(described_class.script_documents(doc)).to eq([])
    end
  end

  describe '.assignment_documents' do
    it 'parses global assignments and ignores other scripts' do
      doc = Nokogiri::HTML(<<~HTML)
        <script>window.STATE = {"b":2}</script>
        <script>console.log(1)</script>
      HTML

      expect(described_class.assignment_documents(doc)).to eq([{ b: 2 }])
    end
  end

  describe '.parse_assignment' do
    it 'parses the payload of a known global assignment' do
      expect(described_class.parse_assignment('window.STATE = {"a":1};')).to eq({ a: 1 })
    end

    it 'returns nil when the text has no known assignment' do
      expect(described_class.parse_assignment('var x = {"a":1};')).to be_nil
    end
  end

  describe '.assignment_payload' do
    it 'returns nil for blank or non-matching text', :aggregate_failures do
      expect(described_class.assignment_payload(nil)).to be_nil
      expect(described_class.assignment_payload('   ')).to be_nil
      expect(described_class.assignment_payload('console.log(1)')).to be_nil
    end

    it 'extracts the JSON object following the assignment' do
      expect(described_class.assignment_payload('window.__NEXT_DATA__ = {"props":{}};')).to eq('{"props":{}}')
    end

    it 'extracts a JSON array following a different assignment' do
      expect(described_class.assignment_payload('self.STATE = [1];')).to eq('[1]')
    end
  end

  describe '.extract_assignment_payload' do
    it 'extracts the balanced JSON block' do
      expect(described_class.extract_assignment_payload('{"a":1}; more')).to eq('{"a":1}')
    end

    it 'returns the text unchanged when it contains no JSON block' do
      expect(described_class.extract_assignment_payload('no json here')).to eq('no json here')
    end
  end

  describe '.extract_json_block' do
    it 'returns the balanced block with surrounding text removed' do
      expect(described_class.extract_json_block('prefix {"a":1} suffix')).to eq('{"a":1}')
    end

    it 'returns the first array block' do
      expect(described_class.extract_json_block('x = [1,2];')).to eq('[1,2]')
    end

    it 'returns nil when there is no opening token or the block is unbalanced', :aggregate_failures do
      expect(described_class.extract_json_block('no brackets')).to be_nil
      expect(described_class.extract_json_block('{"a":1')).to be_nil
    end
  end

  describe '.scan_for_json_end' do
    let(:json) { '{"a":{"b":[1,2]}}' }

    it 'returns the index of the closing token of the balanced payload' do
      expect(described_class.scan_for_json_end("#{json} tail", 0)).to eq(json.length - 1)
    end

    it 'returns the end of a top-level array' do
      expect(described_class.scan_for_json_end('[1,2]', 0)).to eq(4)
    end

    it 'treats an empty string key as a closed string' do
      expect(described_class.scan_for_json_end('{"":{}}', 0)).to eq(6)
    end

    it 'scans from the given start index' do
      expect(described_class.scan_for_json_end("xx#{json}", 2)).to eq(json.length + 1)
    end

    it 'ignores brackets inside strings' do
      text = '{"a":"}]{["}'

      expect(described_class.scan_for_json_end(text, 0)).to eq(text.length - 1)
    end

    it 'honours escaped quotes inside strings' do
      text = '{"a":"x\\"}"}'

      expect(described_class.scan_for_json_end(text, 0)).to eq(text.length - 1)
    end

    it 'honours escaped backslashes before a closing quote' do
      text = '{"a":"x\\\\"}'

      expect(described_class.scan_for_json_end(text, 0)).to eq(text.length - 1)
    end

    it 'returns the end of the first balanced object only' do
      expect(described_class.scan_for_json_end('{}{}', 0)).to eq(1)
    end

    it 'returns nil for unbalanced or mismatched brackets', :aggregate_failures do
      expect(described_class.scan_for_json_end('{"a":1', 0)).to be_nil
      expect(described_class.scan_for_json_end('[1}', 0)).to be_nil
    end
  end

  describe '.parse_json' do
    it 'parses valid JSON with symbolized keys' do
      expect(described_class.parse_json('{"a":1}')).to eq({ a: 1 })
    end

    it 'falls back to JavaScript object coercion' do
      expect(described_class.parse_json('{a: 1,}')).to eq({ a: 1 })
    end

    it 'returns nil for nil input' do
      expect(described_class.parse_json(nil)).to be_nil
    end

    it 'returns nil when the payload cannot be parsed even after coercion' do
      expect(described_class.parse_json('{nope')).to be_nil
    end
  end

  describe '.parse_js_object' do
    it 'parses a coerced JavaScript object literal' do
      expect(described_class.parse_js_object('{a: 1}', nil)).to eq({ a: 1 })
    end

    it 'logs and returns nil when the coerced payload is still invalid', :aggregate_failures do
      allow(Html2rss::Log).to receive(:debug)

      expect(described_class.parse_js_object('{nope', nil)).to be_nil
      expect(Html2rss::Log).to have_received(:debug)
        .with(a_string_matching(/\AJsonState: failed to parse coerced JavaScript object \(\S.*\)\z/))
    end
  end

  describe '.coerce_javascript_object' do
    it 'quotes keys and strips trailing commas' do
      expect(described_class.coerce_javascript_object('{a: 1,}')).to eq('{"a": 1}')
    end
  end

  describe '.quote_unquoted_keys' do
    it 'quotes keys at the start of the payload and after separators', :aggregate_failures do
      expect(described_class.quote_unquoted_keys('a: 1')).to eq('"a": 1')
      expect(described_class.quote_unquoted_keys('{a: 1,b: 2}')).to eq('{"a": 1,"b": 2}')
      expect(described_class.quote_unquoted_keys('[x : 3]')).to eq('["x" : 3]')
      expect(described_class.quote_unquoted_keys('{ a: 1, b : 2 }')).to eq('{ "a": 1, "b" : 2 }')
      expect(described_class.quote_unquoted_keys('  a: 1')).to eq('  "a": 1')
    end

    it 'leaves colons inside string values untouched' do
      expect(described_class.quote_unquoted_keys('{k: "a: b"}')).to eq('{"k": "a: b"}')
    end
  end

  describe '.strip_trailing_commas' do
    it 'removes commas directly before closing tokens', :aggregate_failures do
      expect(described_class.strip_trailing_commas('[1, 2,]')).to eq('[1, 2]')
      expect(described_class.strip_trailing_commas("{\"a\": 1,\n}")).to eq("{\"a\": 1\n}")
      expect(described_class.strip_trailing_commas('[[1,],[2,]]')).to eq('[[1],[2]]')
    end

    it 'keeps commas between values' do
      expect(described_class.strip_trailing_commas('[1, 2]')).to eq('[1, 2]')
    end
  end
end
