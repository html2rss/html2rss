# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::RequestService::Response do
  subject(:instance) { described_class.new(body:, headers:, url: Html2rss::Url.from_absolute('https://example.com')) }

  let(:build_response) do
    lambda do |body, content_type|
      headers = content_type ? { 'Content-Type' => content_type } : {}
      described_class.new(body:, headers:, url: Html2rss::Url.from_absolute('https://example.com'))
    end
  end

  describe '#headers' do
    subject(:returned_headers) { instance.headers }

    let(:body) { nil }
    let(:headers) { { key: 42 } }

    it 'returns hash w/ string keys', :aggregate_failures do
      expect(returned_headers).to eq('key' => 42)
      expect(returned_headers).not_to be headers
    end
  end

  describe '#content_type' do # rubocop:disable RSpec/RepeatedExampleGroupDescription
    let(:body) { '' }

    context 'when the response uses canonical header casing' do
      let(:headers) { { 'Content-Type' => 'text/html' } }

      it 'looks up the header case-insensitively' do
        expect(instance.content_type).to eq('text/html')
      end
    end
  end

  describe '#json_response?' do # rubocop:disable RSpec/RepeatedExampleGroupDescription
    [
      { content_type: 'application/json', label: 'application/json' },
      { content_type: 'text/json', label: 'text/json' },
      { content_type: 'text/json; charset=utf-8', label: 'text/json with charset' },
      { content_type: 'application/feed+json', label: 'application/feed+json' },
      { content_type: 'application/vnd.api+json', label: 'application/vnd.api+json' }
    ].each do |example|
      context "when Content-Type is #{example[:label]}" do
        let(:body) { '[]' }
        let(:headers) { { 'content-type' => example[:content_type] } }

        it 'is a JSON body, not HTML and not a syndication feed', :aggregate_failures do
          expect(instance.json_response?).to be true
          expect(instance.html_response?).to be false
          expect(instance.feed_response?).to be false
        end
      end
    end

    context 'when Content-Type is application/rss+xml' do
      let(:body) { '<?xml version="1.0"?><rss version="2.0"></rss>' }
      let(:headers) { { 'content-type' => 'application/rss+xml' } }

      it 'is a syndication feed, not JSON', :aggregate_failures do
        expect(instance.json_response?).to be false
        expect(instance.feed_response?).to be true
      end
    end
  end

  describe '#html_response?' do # rubocop:disable RSpec/RepeatedExampleGroupDescription
    [
      { content_type: 'application/octet-stream', label: 'octet-stream' },
      { content_type: '', label: 'empty' },
      { content_type: 'text/plain', label: 'wrong' }
    ].each do |example|
      context "when Content-Type is #{example[:label]} but the body looks like HTML" do
        let(:body) { "<!DOCTYPE html><html><body><div>#{example[:label]}</div></body></html>" }
        let(:headers) { example[:content_type].empty? ? {} : { 'content-type' => example[:content_type] } }

        it 'treats sniffed HTML as an HTML response so Capture and Inspect do not skip SST' do
          expect(instance.html_response?).to be true
        end
      end
    end

    context 'when the response is JSON' do
      let(:body) { '{"html":"<html></html>"}' }
      let(:headers) { { 'content-type' => 'application/json' } }

      it 'does not treat JSON as HTML even when the payload mentions markup' do
        expect(instance.html_response?).to be false
      end
    end

    context 'when Content-Type is octet-stream and the body is not HTML' do
      let(:body) { "PK\x03\x04not-html" }
      let(:headers) { { 'content-type' => 'application/octet-stream' } }

      it { expect(instance.html_response?).to be false }
    end

    context 'when the response is RSS' do
      let(:body) { '<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>' }
      let(:headers) { { 'content-type' => 'application/rss+xml' } }

      it { expect(instance.html_response?).to be false }
    end
  end

  describe '#feed_response?' do # rubocop:disable RSpec/RepeatedExampleGroupDescription
    context 'when Content-Type advertises RSS' do
      let(:body) { '<?xml version="1.0"?><rss version="2.0"></rss>' }
      let(:headers) { { 'content-type' => 'application/rss+xml' } }

      it { expect(instance.feed_response?).to be true }
    end

    context 'when Content-Type is wrong but the body sniffs as Atom' do
      let(:body) { '<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"></feed>' }
      let(:headers) { { 'content-type' => 'text/plain' } }

      it { expect(instance.feed_response?).to be true }
    end

    context 'when the response is HTML' do
      let(:body) { '<!DOCTYPE html><html><body>hi</body></html>' }
      let(:headers) { { 'content-type' => 'text/html' } }

      it { expect(instance.feed_response?).to be false }
    end

    context 'when Content-Type is image/svg+xml' do
      let(:body) { '<svg xmlns="http://www.w3.org/2000/svg"></svg>' }
      let(:headers) { { 'content-type' => 'image/svg+xml' } }

      it { expect(instance.feed_response?).to be false }
    end
  end

  describe '#parsed_body' do
    subject(:parsed_body) { instance.parsed_body }

    context 'when the response is HTML' do
      let(:body) do
        <<-HTML
      <html>
        <body>
          <!-- This is a comment -->
          <div>Hello World</div>
        </body>
      </html>
        HTML
      end
      let(:headers) { { 'content-type' => 'text/html' } }

      it { expect(parsed_body).to be_frozen }

      it 'parses the body and removes comments', :aggregate_failures do
        expect(parsed_body.at_xpath('//comment()')).to be_nil
        expect(parsed_body.at_css('div').text).to eq('Hello World')
      end
    end

    context 'when the response is JSON' do
      let(:body) { '{"key": "value"}' }
      let(:headers) { { 'content-type' => 'application/json' } }

      it { expect(parsed_body).to be_frozen }

      it 'parses the body as JSON' do
        expect(parsed_body).to eq({ key: 'value' })
      end
    end

    context 'when Content-Type is text/json' do
      let(:body) { '[{"name":"Example App"}]' }
      let(:headers) { { 'content-type' => 'text/json' } }

      it 'parses the body as JSON so listing URLs are not UnsupportedResponseContentType' do
        expect(parsed_body).to eq([{ name: 'Example App' }])
      end
    end

    context 'when the response content type is not supported' do
      let(:body) { 'Some unsupported content' }
      let(:headers) { { 'content-type' => 'text/plain' } }

      it 'raises an UnsupportedResponseContentType error' do
        expect do
          parsed_body
        end.to raise_error(Html2rss::RequestService::UnsupportedResponseContentType,
                           'Unsupported content type: text/plain')
      end
    end

    [
      { content_type: 'application/octet-stream', label: 'octet-stream' },
      { content_type: '', label: 'empty' },
      { content_type: 'text/plain', label: 'wrong' }
    ].each do |example|
      context "when Content-Type is #{example[:label]} but the body looks like HTML" do
        let(:body) { "<!DOCTYPE html><html><body><div>#{example[:label]}</div></body></html>" }
        let(:headers) { example[:content_type].empty? ? {} : { 'content-type' => example[:content_type] } }

        it 'parses the HTML document' do
          expect(parsed_body.at_css('div').text).to eq(example[:label])
        end
      end
    end

    context 'when Content-Type is octet-stream and the body is not HTML' do
      let(:body) { "PK\x03\x04not-html" }
      let(:headers) { { 'content-type' => 'application/octet-stream' } }

      it 'raises UnsupportedResponseContentType' do
        expect { parsed_body }
          .to raise_error(Html2rss::RequestService::UnsupportedResponseContentType,
                          'Unsupported content type: application/octet-stream')
      end
    end

    [
      {
        label: 'Content-Type charset',
        headers: { 'content-type' => 'text/html; charset=windows-1252' },
        html: '<!DOCTYPE html><html><body><h1>Caffè</h1></body></html>'
      },
      {
        label: 'meta charset',
        headers: { 'content-type' => 'text/html' },
        html: '<!DOCTYPE html><html><head><meta charset="windows-1252"></head>' \
              '<body><h1>Caffè</h1></body></html>'
      }
    ].each do |example|
      context "when windows-1252 HTML uses #{example[:label]}" do
        let(:body) { example[:html].encode('Windows-1252').force_encoding(Encoding::UTF_8) }
        let(:headers) { example[:headers] }

        it 'decodes Caffè instead of mojibake' do
          expect(parsed_body.at_css('h1').text).to eq('Caffè')
        end
      end
    end
  end

  describe '#initialize' do
    let(:url) { Html2rss::Url.from_absolute('https://example.com') }
    let(:empty_meta) { described_class::EMPTY_TRANSPORT_META }
    let(:empty_captures) { described_class::EMPTY_CAPTURED_RESPONSES }

    it 'exposes body, url and status', :aggregate_failures do
      response = described_class.new(body: 'b', url:, status: 204)

      expect(response).to have_attributes(body: 'b', url:, status: 204, headers: {})
    end

    it 'stringifies header names but keeps header values as given', :aggregate_failures do
      response = described_class.new(body: 'b', url:, headers: { key: 42 })

      expect(response.headers).to eq('key' => 42)
      expect(response.headers.keys).to all(be_a(String))
    end

    it 'defaults status to nil and shares the frozen empty telemetry', :aggregate_failures do
      response = described_class.new(body: 'b', url:)

      expect(response.status).to be_nil
      expect(response.transport_meta).to equal(empty_meta)
      expect(response.captured_responses).to equal(empty_captures)
    end

    it 'treats nil and empty telemetry as the shared empty values', :aggregate_failures do
      response = described_class.new(body: 'b', url:, headers: nil, transport_meta: nil, captured_responses: nil)
      other = described_class.new(body: 'b', url:, transport_meta: {}, captured_responses: [])

      expect(response.headers).to eq({})
      expect([response.transport_meta, other.transport_meta]).to all(equal(empty_meta))
      expect([response.captured_responses, other.captured_responses]).to all(equal(empty_captures))
    end

    it 'freezes provided telemetry', :aggregate_failures do
      response = described_class.new(body: 'b', url:, transport_meta: { a: 1 }, captured_responses: [{ b: 2 }])

      expect(response.transport_meta).to eq(a: 1)
      expect(response.transport_meta).to be_frozen
      expect(response.captured_responses).to eq([{ b: 2 }])
      expect(response.captured_responses).to be_frozen
    end

    it 'defaults cookies to the shared frozen empty map', :aggregate_failures do
      response = described_class.new(body: 'b', url:)

      expect(described_class::EMPTY_COOKIES).to be_frozen
      expect(response.cookies).to equal(described_class::EMPTY_COOKIES)
    end

    it 'freezes provided cookies', :aggregate_failures do
      response = described_class.new(body: 'b', url:, cookies: { 'datadome' => 'abc' })

      expect(response.cookies).to eq('datadome' => 'abc')
      expect(response.cookies).to be_frozen
    end

    it 'treats nil and empty cookies as the shared empty map', :aggregate_failures do
      expect(described_class.new(body: 'b', url:, cookies: nil).cookies).to equal(described_class::EMPTY_COOKIES)
      expect(described_class.new(body: 'b', url:, cookies: {}).cookies).to equal(described_class::EMPTY_COOKIES)
    end
  end

  describe '#json_response?' do # rubocop:disable RSpec/RepeatedExampleGroupDescription
    {
      'application/json' => true, 'APPLICATION/JSON; charset=utf-8' => true, ' application/json ' => true,
      'application/ld+json' => true, 'text/json' => true, 'application/jsonp' => false,
      'text/plain; profile="x/json"' => false, 'application/rss+xml' => false, '' => false
    }.each do |type, expected|
      it "is #{expected} for #{type.inspect}" do
        expect(build_response.call('', type).json_response?).to be(expected)
      end
    end
  end

  describe '#feed_content_type?' do
    {
      'application/rss+xml' => true, 'application/atom+xml' => true, 'application/rss' => true,
      'application/atom' => true, 'APPLICATION/RSS+XML; charset=utf-8' => true, 'text/xml' => false,
      'application/xml' => false, 'text/html; x=rss' => false, 'application/json; x=rss' => false, '' => false
    }.each do |type, expected|
      it "makes feed_response? #{expected} for header #{type.inspect} with an empty body" do
        expect(build_response.call('', type).feed_response?).to be(expected)
      end
    end
  end

  describe '#feed_looking_body?' do
    {
      '<rss version="2.0">' => true, '<feed xmlns="x">' => true, '<feed version="1">' => true,
      '<RSS>' => true, "#{' ' * 790}<rss" => true, "#{' ' * 800}<rss" => false,
      '<feed>' => false, 'plain text' => false, '<!DOCTYPE html><rss>' => false, "<html>\n<feed xmlns" => false,
      "#{' ' * 796}<rss" => true, "#{' ' * 797}<rss" => false
    }.each do |body, expected|
      it "makes feed_response? #{expected} for unlabeled body #{body[0, 30].inspect}" do
        expect(build_response.call(body, nil).feed_response?).to be(expected)
      end
    end

    it 'does not sniff a feed body when the response is JSON' do
      expect(build_response.call('<rss>', 'application/json').feed_response?).to be(false)
    end

    it 'treats a nil body as an empty unlabeled body' do
      expect(build_response.call(nil, nil).feed_response?).to be(false)
    end

    it 'does not raise on an unlabeled body with invalid UTF-8', :aggregate_failures do
      response = build_response.call("\xFF<rss>".dup.force_encoding('UTF-8'), nil)

      expect(response.feed_response?).to be(true)
      expect(response.html_response?).to be(false)
    end
  end

  describe '#html_looking_body?' do
    {
      '<!DOCTYPE html><p>' => true, "  \n<!doctype HTML>" => true, '<html lang="en">' => true, '<HTML>' => true,
      '<!DOCTYPE svg>' => false, 'x <html>' => false, '<div>' => false, '' => false
    }.each do |body, expected|
      it "makes html_response? #{expected} for unlabeled body #{body.inspect}" do
        expect(build_response.call(body, nil).html_response?).to be(expected)
      end
    end

    it 'sniffs an HTML body that carries invalid UTF-8 bytes' do
      response = build_response.call("<html>\xFF".dup.force_encoding(Encoding::UTF_8), nil)

      expect(response.html_response?).to be(true)
    end
  end

  describe '#html_response?' do # rubocop:disable RSpec/RepeatedExampleGroupDescription
    it 'treats text/html as html regardless of body, but never json or feed types', :aggregate_failures do
      expect(build_response.call('{}', 'text/html').html_response?).to be(true)
      expect(build_response.call('<html>', 'application/json').html_response?).to be(false)
      expect(build_response.call('<html><rss>', 'application/rss+xml').html_response?).to be(false)
    end
  end

  describe '#feed_response?' do # rubocop:disable RSpec/RepeatedExampleGroupDescription
    it 'never sniffs feed markers out of json or html bodies', :aggregate_failures do
      expect(build_response.call('<rss>', 'application/json').feed_response?).to be(false)
      expect(build_response.call('<!DOCTYPE html><rss>', nil).feed_response?).to be(false)
      expect(build_response.call('<rss>', nil).feed_response?).to be(true)
    end

    it 'memoizes feed detection', :aggregate_failures do
      response = build_response.call('', 'application/rss+xml')

      expect(response.feed_response?).to be(true)

      response.headers['content-type'] = 'text/html'
      expect(response.feed_response?).to be(true)
    end

    it 'memoizes a negative feed detection too', :aggregate_failures do
      response = build_response.call('<rss>', 'application/json')

      expect(response.feed_response?).to be(false)

      response.headers['content-type'] = 'application/rss+xml'
      expect(response.feed_response?).to be(false)
    end
  end

  describe '#header' do
    it 'looks up headers case-insensitively', :aggregate_failures do
      response = described_class.new(body: '', headers: { 'CONTENT-TYPE' => 'application/rss+xml' },
                                     url: Html2rss::Url.from_absolute('https://example.com'))

      expect(response.content_type).to eq('application/rss+xml')
      expect(response.headers.fetch('CONTENT-TYPE')).to eq('application/rss+xml')
    end

    it 'ignores headers with other names' do
      response = described_class.new(body: '', headers: { 'X-Content-Type' => 'text/html' },
                                     url: Html2rss::Url.from_absolute('https://example.com'))

      expect(response.content_type).to eq('')
    end

    it 'prefers an exact-case header key over a case-insensitive match', :aggregate_failures do
      headers = { 'Content-Type' => 'text/plain', 'content-type' => 'application/rss+xml' }
      response = described_class.new(body: '', headers:, url: Html2rss::Url.from_absolute('https://example.com'))

      expect(response.content_type).to eq('application/rss+xml')
    end
  end

  describe '#content_type' do # rubocop:disable RSpec/RepeatedExampleGroupDescription
    it 'returns a string even for a nil header value or a missing header', :aggregate_failures do
      response = described_class.new(body: '', headers: { 'content-type' => nil },
                                     url: Html2rss::Url.from_absolute('https://example.com'))

      expect(response.content_type).to eq('')
      expect(build_response.call('', nil).content_type).to eq('')
    end
  end

  context 'with HTML decoding' do
    let(:headers) { { 'Content-Type' => 'text/html' } }
    let(:url) { Html2rss::Url.from_absolute('https://example.com') }

    describe '#decoded_html_body' do
      it 'decodes a quoted charset parameter with spaces around the equals sign' do
        response = described_class.new(
          body: "<p>Caff\xE8</p>".b, headers: { 'Content-Type' => "text/html; charset = 'iso-8859-1'" }, url:
        )

        expect(response.parsed_body.at_css('p').text).to eq('Caffè')
      end

      it 'prefers the header charset over the meta charset' do
        response = described_class.new(
          body: "<meta charset=\"shift_jis\"><p>Caff\xE8</p>".b,
          headers: { 'Content-Type' => 'text/html; charset=iso-8859-1' }, url:
        )

        expect(response.parsed_body.at_css('p').text).to eq('Caffè')
      end

      it 'treats a nil body as an empty document' do
        expect(described_class.new(body: nil, headers:, url:).parsed_body.text).to eq('')
      end
    end

    describe '#meta_charset' do
      it 'scans from the first byte of the body' do
        response = described_class.new(body: "charset=iso-8859-1 Caff\xE8".b, headers:, url:)

        expect(response.parsed_body.text).to include('Caffè')
      end

      it 'reads a meta charset inside the first 2048 bytes only', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        early = described_class.new(body: "<meta charset=iso-8859-1><p>Caff\xE8</p>".b, headers:, url:)
        late = described_class.new(
          body: "<!-- #{'x' * 2100} --><meta charset=iso-8859-1><p>Caff\xE8</p>".b, headers:, url:
        )

        expect(early.parsed_body.at_css('p').text).to eq('Caffè')
        expect(late.parsed_body.at_css('p').text).to include('�')
      end
    end

    describe '#utf8_charset?' do
      ['UTF-8', 'utf8', 'UTF_8', 'utf 8', 'Utf-8'].each do |charset|
        it "treats #{charset} as UTF-8 and scrubs invalid bytes" do
          response = described_class.new(
            body: "<p>ok \xFF</p>".b, headers: { 'Content-Type' => "text/html; charset=#{charset}" }, url:
          )

          expect(response.parsed_body.at_css('p').text).to eq('ok �')
        end
      end

      it 'does not treat other charsets as UTF-8' do
        response = described_class.new(
          body: "<p>\xE8</p>".b, headers: { 'Content-Type' => 'text/html; charset=iso-8859-1' }, url:
        )

        expect(response.parsed_body.at_css('p').text).to eq('è')
      end
    end

    describe '#html_encoding_for' do
      it 'scrubs when the charset is unknown' do
        response = described_class.new(
          body: "<p>\xFF</p>".b, headers: { 'Content-Type' => 'text/html; charset=bogus-charset' }, url:
        )

        expect(response.parsed_body.at_css('p').text).to eq('�')
      end
    end

    describe '#transcode_html' do
      it 'scrubs when the bytes are invalid for the declared charset' do
        response = described_class.new(
          body: "<p>\xFF\xFF</p>".b, headers: { 'Content-Type' => 'text/html; charset=shift_jis' }, url:
        )

        expect(response.parsed_body.at_css('p').text).to eq('��')
      end
    end

    describe '#utf8_scrub' do
      it 'keeps valid UTF-8 untouched and replaces invalid bytes without a charset', :aggregate_failures do
        valid = described_class.new(body: '<p>Caffè</p>', headers:, url:)
        invalid = described_class.new(body: "<p>a\xFFb</p>".b, headers:, url:)

        expect(valid.parsed_body.at_css('p').text).to eq('Caffè')
        expect(invalid.parsed_body.at_css('p').text).to eq('a�b')
      end
    end

    describe '#parsed_body' do
      it 'memoizes the parsed body' do
        response = described_class.new(body: '<p>x</p>', headers:, url:)

        expect(response.parsed_body).to equal(response.parsed_body)
      end

      it 'freezes parsed JSON with symbolized keys', :aggregate_failures do
        response = described_class.new(body: '{"a":{"b":1}}', headers: { 'Content-Type' => 'application/json' }, url:)

        expect(response.parsed_body).to eq(a: { b: 1 })
        expect(response.parsed_body).to be_frozen
      end

      it 'names the content type when it is unsupported' do
        response = described_class.new(body: 'x', headers: { 'Content-Type' => 'image/png' }, url:)

        expect { response.parsed_body }
          .to raise_error(Html2rss::RequestService::UnsupportedResponseContentType,
                          'Unsupported content type: image/png')
      end
    end
  end

  describe '#url' do
    let(:body) { '' }
    let(:headers) { {} }

    it 'returns the request URL' do
      expect(instance.url.to_s).to eq('https://example.com/')
    end
  end

  describe '#captured_responses' do
    let(:body) { '' }
    let(:headers) { {} }

    it 'defaults to an empty frozen array', :aggregate_failures do
      expect(instance.captured_responses).to eq([])
      expect(instance.captured_responses).to be_frozen
    end

    it 'stores captured responses when provided', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      captured = [{ 'url' => 'https://api.example/items', 'body' => '[]' }]
      response = described_class.new(
        body: '',
        headers: {},
        url: Html2rss::Url.from_absolute('https://example.com'),
        captured_responses: captured
      )

      expect(response.captured_responses).to eq(captured)
      expect(response.captured_responses).to be_frozen
    end
  end
end
