# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Selectors::PostProcessors::HtmlTransformers::KeepPlayableMedia do
  subject(:transformer) { described_class.new('https://example.com/list/') }

  describe '#call' do
    let(:fragment) { Nokogiri::HTML.fragment(%(<p>#{markup}</p>)) }
    let(:node) { fragment.at_css(node_name) }
    let(:transform) { transformer.call(node_name:, node:) }

    context 'with a relative src on a player' do
      let(:markup) { '<audio src="ep.mp3"></audio>' }
      let(:node_name) { 'audio' }

      it 'makes the src absolute and keeps the player', :aggregate_failures do
        expect(transform).to be_nil
        expect(fragment.at_css('audio')['src']).to eq('https://example.com/list/ep.mp3')
      end
    end

    context 'with an http src on a source' do
      let(:markup) { '<video><source src="http://example.net/v.mp4"></video>' }
      let(:node_name) { 'source' }

      it 'keeps it' do
        transform
        expect(fragment.at_css('source')['src']).to eq('http://example.net/v.mp4')
      end
    end

    context 'with a player whose own src is unplayable but a source child is playable' do
      let(:markup) { '<video src="javascript:x()"><source src="/v.mp4"></video>' }
      let(:node_name) { 'video' }

      it 'removes only the src attribute', :aggregate_failures do
        transform
        expect(fragment.at_css('video').key?('src')).to be(false)
        expect(fragment.at_css('video source')['src']).to eq('/v.mp4')
      end
    end

    {
      'audio' => ['<audio src="data:audio/mp3;base64,AA"></audio>', '<audio>fallback</audio>',
                  '<audio src=""><source src="mailto:a@example.com"></audio>'],
      'video' => ['<video src="http://exa mple.com/v.mp4"></video>', '<video><source></video>'],
      'source' => ['<source src="javascript:x()">', '<source type="video/mp4">']
    }.each_pair do |name, markups|
      markups.each do |markup|
        context "with #{markup}" do
          let(:markup) { markup }
          let(:node_name) { name }

          it "drops the #{name}" do
            transform
            expect(fragment.at_css(name)).to be_nil
          end
        end
      end
    end

    context 'with another element' do
      let(:markup) { '<img src="javascript:x()">' }
      let(:node_name) { 'img' }

      it 'leaves it alone' do
        transform
        expect(fragment.at_css('img')['src']).to eq('javascript:x()')
      end
    end
  end
end
