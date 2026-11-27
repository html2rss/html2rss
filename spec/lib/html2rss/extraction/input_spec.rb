# frozen_string_literal: true

RSpec.describe Html2rss::Extraction::Input do
  let(:error) { described_class::InvalidError }
  let(:page) { { url: 'https://example.com/', body: '<p></p>', headers: { 'content-type' => 'text/html' } } }

  describe '.page' do
    it 'reads a page by symbol or string keys', :aggregate_failures do
      expect(described_class.page(page)).to eq(page)
      expect(described_class.page(page.transform_keys(&:to_s))).to eq(page)
    end

    it 'keeps the optional headers out of the required keys' do
      expect(described_class.page(page.except(:headers))).to eq(page.except(:headers))
    end

    it 'names what a page lacks', :aggregate_failures do
      expect { described_class.page(page.except(:url)) }.to raise_error(error, 'missing url')
      expect { described_class.page({}) }.to raise_error(error, 'missing url, body')
    end

    it 'reads a Hash subclass' do
      expect(described_class.page(Class.new(Hash)[page])).to eq(page)
    end

    it 'names what it got in place of a hash' do
      expect { described_class.page('page') }.to raise_error(error, 'expected a hash, got String')
    end
  end

  describe '.responses' do
    let(:answer) { { url: 'https://example.com/feed', body: '<rss/>' } }

    it 'reads ids as strings and answers by symbol or string keys', :aggregate_failures do
      expect(described_class.responses({ 'a' => answer })).to eq('a' => answer)
      expect(described_class.responses({ a: answer.transform_keys(&:to_s) })).to eq('a' => answer)
    end

    it 'reads a failure by symbol or string key, with the kind as a symbol', :aggregate_failures do
      expect(described_class.responses({ 'a' => { error_kind: :timeout } })).to eq('a' => { error_kind: :timeout })
      expect(described_class.responses({ 'a' => { 'error_kind' => 'budget' } })).to eq('a' => { error_kind: :budget })
    end

    it 'refuses an unknown kind, naming it', :aggregate_failures do
      expect { described_class.responses({ 'a' => { error_kind: 'nope' } }) }
        .to raise_error(error, 'unknown error kind: "nope"')
      expect { described_class.responses({ 'a' => { error_kind: 5 } }) }.to raise_error(error, 'unknown error kind: 5')
    end

    it 'refuses an answer that lacks its page parts', :aggregate_failures do
      missing = ->(answer) { described_class.responses({ 'a' => answer }) }

      expect { missing.call({ url: 'https://example.com/' }) }.to raise_error(error, 'missing body')
      expect { missing.call({ body: '<p></p>' }) }.to raise_error(error, 'missing url')
      expect { missing.call('x') }.to raise_error(error, 'expected a hash, got String')
    end

    it 'reads Hash subclasses for the responses and their answers' do
      answers = Class.new(Hash)['a' => Class.new(Hash)[{ error_kind: :timeout }]]

      expect(described_class.responses(answers)).to eq('a' => { error_kind: :timeout })
    end

    it 'refuses responses that are not a hash' do
      expect { described_class.responses([]) }.to raise_error(error, 'responses must be a hash, got Array')
    end
  end
end
