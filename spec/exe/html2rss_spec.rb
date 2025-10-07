# frozen_string_literal: true

RSpec.describe 'exe/html2rss', :slow do
  let(:executable) do
    matches = Gem::Specification.find_all_by_name 'html2rss'
    spec = matches.first

    File.expand_path('exe/html2rss', spec.full_gem_path)
  end

  let(:doctype_xml) do
    '<?xml version="1.0" encoding="UTF-8"?>'
  end

  let(:stylesheets_xml) do
    <<~XML
      <?xml-stylesheet href="/style.xls" type="text/xsl" media="all"?>
      <?xml-stylesheet href="/rss.css" type="text/css" media="all"?>
    XML
  end

  let(:rss_xml) do
    <<~RSS
      <rss version="2.0"
        xmlns:content="http://purl.org/rss/1.0/modules/content/"
        xmlns:dc="http://purl.org/dc/elements/1.1/"
        xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"
        xmlns:trackback="http://madskills.com/public/xml/rss/module/trackback/">
    RSS
  end

  let(:rss_title_pattern) { %r{<title>.+</title>} }

  context 'without any arguments' do
    it 'prints usage information' do
      expect(`#{executable}`).to start_with("Commands:\n  html2rss")
    end
  end

  context 'without argument: help' do
    it 'prints usage information' do
      expect(`#{executable} help`).to start_with("Commands:\n  html2rss")
    end
  end

  context 'with feed config: nuxt-releases' do
    context 'with arguments: feed YAML_FILE' do
      subject(:output) do
        capture_cli_output('feed', 'spec/fixtures/single.test.yml', cassette: 'nuxt-releases')
      end

      it 'generates the RSS', :aggregate_failures do
        expect(output).to start_with(doctype_xml)
        expect(output).not_to include(stylesheets_xml)
        expect(output).to include(rss_xml)
        expect(output).to match(rss_title_pattern)
      end
    end

    context 'with arguments: feed YAML_FILE FEED_NAME' do
      subject(:output) do
        capture_cli_output('feed', 'spec/fixtures/feeds.test.yml', 'nuxt-releases', cassette: 'nuxt-releases')
      end

      it 'generates the RSS', :aggregate_failures do
        expect(output).to start_with(doctype_xml)
        expect(output).to include(stylesheets_xml)
        expect(output).to include(rss_xml)
        expect(output).to match(rss_title_pattern)
      end
    end
  end

  context 'with feed config: withparams' do
    subject(:output) do
      capture_cli_output('feed', 'spec/fixtures/feeds.test.yml', 'withparams', '--params', 'sign:10', 'param:value',
                         cassette: 'notitle')
    end

    it 'processes and escapes the params' do
      expect(output)
        .to include('<description>The value of param is: value</description>',
                    'horoscope-general-daily-today.aspx?sign=10</link>')
    end
  end

  context 'with argument: auto URL' do
    it 'exists with error' do
      `#{executable} auto file://etc/passwd`
      expect($?.exitstatus).to eq(1) # rubocop:disable Style/SpecialGlobalVars
    end
  end
end
