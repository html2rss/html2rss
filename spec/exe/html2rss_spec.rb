# frozen_string_literal: true

RSpec.describe 'exe/html2rss' do
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
        <channel>
          <title>github.com: Nuxt Nuxt.js Releases</title>
    RSS
  end

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
      subject(:output) { `#{executable} feed spec/single.test.yml` }

      it 'generates the RSS', :aggregate_failures do
        expect(output).to start_with(doctype_xml)
        expect(output).not_to include(stylesheets_xml)
        expect(output).to include(rss_xml)
      end
    end

    context 'with arguments: feed YAML_FILE FEED_NAME' do
      subject(:output) { `#{executable} feed spec/feeds.test.yml nuxt-releases` }

      it 'generates the RSS', :aggregate_failures do
        expect(output).to start_with(doctype_xml)
        expect(output).to include(stylesheets_xml)
        expect(output).to include(rss_xml)
      end
    end
  end

  context 'with feed config: withparams' do
    it 'processes and escapes the params' do
      expect(`#{executable} feed spec/feeds.test.yml withparams param='<value>' sign=10`)
        .to include('<description>The value of param is: &lt;value&gt;</description>',
                    'horoscope-general-daily-today.aspx?sign=10')
    end
  end

  context 'with argument: auto URL' do
    subject(:output) { `#{executable} auto #{url}` }

    let(:url) { 'https://welt.de' }

    it 'generates the RSS', :aggregate_failures do
      expect(output).to start_with(doctype_xml) &
                        include(url) &
                        end_with(<<~XML)
                              <generator>html2rss [autosourced] V. #{Html2rss::VERSION}</generator>
                            </channel>
                          </rss>
                        XML
    end
  end
end
