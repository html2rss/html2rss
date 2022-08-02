# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Config::Channel do
  describe '#url' do
    subject { described_class.new(hash, params: params).url }

    let(:params) { {} }

    context 'with non-ascii url and without dynamic parameters' do
      let(:hash) do
        { url: 'https://例子.測試/23/' }
      end

      it do
        expect(subject).to eq Addressable::URI.parse('https://例子.測試/23/')
      end
    end

    context 'with non-ascii url and with dynamic parameters' do
      let(:hash) do
        { url: 'https://例子.測試/%<id>s/' }
      end

      let(:params) { { id: 42 } }

      it do
        expect(subject).to eq Addressable::URI.parse('https://例子.測試/42/')
      end
    end
  end
end
