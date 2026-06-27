# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Html2rss::RequestService::LocalFileStrategy do
  subject(:execute) { described_class.new(ctx).execute }

  let(:file_path) { temp_file.path }
  let(:temp_file) do
    Tempfile.new(%w[test .html]).tap do |f|
      f.write('<html><body><h1>Hello World</h1></body></html>')
      f.close
    end
  end

  after do
    temp_file.unlink
  end

  context 'with a valid file path' do
    let(:ctx) do
      Html2rss::RequestService::Context.new(
        url: 'https://example.com',
        request: { local_file_path: file_path }
      )
    end

    it 'reads the file content and returns a Response object', :aggregate_failures do
      response = execute
      expect(response.body).to eq('<html><body><h1>Hello World</h1></body></html>')
      expect(response.status).to eq(200)
      expect(response.headers['content-type']).to include('text/html')
      expect(response.url.to_s).to eq('https://example.com/')
    end
  end

  context 'with a missing file path' do
    let(:ctx) do
      Html2rss::RequestService::Context.new(
        url: 'https://example.com',
        request: { local_file_path: '/nonexistent/file.html' }
      )
    end

    it 'raises Errno::ENOENT' do
      expect { execute }.to raise_error(Errno::ENOENT)
    end
  end

  context 'without local_file_path in request context' do
    let(:ctx) do
      Html2rss::RequestService::Context.new(
        url: 'https://example.com',
        request: {}
      )
    end

    it 'raises ArgumentError' do
      expect { execute }.to raise_error(ArgumentError, /Local file path is required/)
    end
  end
end
