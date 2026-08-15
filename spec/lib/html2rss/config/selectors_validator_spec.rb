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

      it 'fails validation', :aggregate_failures do
        expect(result).to be_failure
        expect(result.errors.to_h.to_s).to include('`strategy` must be one of')
      end
    end

    context 'with custom_selector strategy missing selector' do
      let(:config) do
        { items: { selector: '.article', pagination: { strategy: 'custom_selector' } } }
      end

      it 'fails validation', :aggregate_failures do
        expect(result).to be_failure
        expect(result.errors.to_h.to_s).to include('`custom_selector` strategy requires `selector`')
      end
    end

    context 'with json_cursor strategy missing cursor_path or next_url_path' do
      let(:config) do
        { items: { selector: '.article', pagination: { strategy: 'json_cursor' } } }
      end

      it 'fails validation', :aggregate_failures do
        msg = '`json_cursor` strategy requires either `cursor_path` or `next_url_path`'
        expect(result).to be_failure
        expect(result.errors.to_h.to_s).to include(msg)
      end
    end

    context 'with invalid pagination max_pages' do
      let(:config) do
        { items: { selector: '.article', pagination: { max_pages: 0 } } }
      end

      it 'fails validation', :aggregate_failures do
        expect(result).to be_failure
        expect(result.errors.to_h.to_s).to include('must be an integer greater than 0')
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
        expect(result.errors.to_h.to_s).to include('`max_pages` must be an integer greater than 0')
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

    context 'with html_to_markdown' do
      let(:config) do
        { title: { post_process: [{ name: 'html_to_markdown' }] } }
      end

      it { is_expected.to be_success }
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

      it { expect(result).to be_failure }
    end

    it 'requires Options members from the extractor registry', :aggregate_failures do
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

      it { expect(result).to be_failure }
    end
  end
end
