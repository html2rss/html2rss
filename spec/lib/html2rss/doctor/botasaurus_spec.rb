# frozen_string_literal: true

require 'spec_helper'
require 'climate_control'

RSpec.describe Html2rss::Doctor::Botasaurus do
  describe '.call' do
    it 'reports missing env without leaking secrets', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      ClimateControl.modify(BOTASAURUS_SCRAPER_URL: nil) do
        result = described_class.call

        expect(result.ok).to be(false)
        expect(result.message).to include('BOTASAURUS_SCRAPER_URL')
        expect(result.checks.first.detail).to include(var: 'BOTASAURUS_SCRAPER_URL')
      end
    end

    it 'passes when health responds 200', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      conn = instance_double(Faraday::Connection)
      response = instance_double(Faraday::Response, status: 200, body: '{"version":"1.2.3"}')
      allow(Faraday).to receive(:new).and_return(conn)
      allow(conn).to receive(:get).with('/health').and_return(response)

      ClimateControl.modify(BOTASAURUS_SCRAPER_URL: 'http://127.0.0.1:4010') do
        result = described_class.call

        expect(result.ok).to be(true)
        expect(result.checks.map(&:name)).to include(:env, :health)
        expect(result.to_h).to include(ok: true, message: 'Botasaurus preflight passed.')
      end
    end

    it 'fails when health responds non-200', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      conn = instance_double(Faraday::Connection)
      response = instance_double(Faraday::Response, status: 503, body: '{}')
      allow(Faraday).to receive(:new).and_return(conn)
      allow(conn).to receive(:get).with('/health').and_return(response)

      ClimateControl.modify(BOTASAURUS_SCRAPER_URL: 'http://127.0.0.1:4010') do
        result = described_class.call

        expect(result.ok).to be(false)
        expect(result.message).to eq('Botasaurus health check failed.')
        expect(result.checks.find { |check| check.name == :health }.detail).to include(status: 503, ok: false)
      end
    end

    it 'fails when health request raises', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      allow(Faraday).to receive(:new).and_raise(Faraday::ConnectionFailed, 'connection refused')

      ClimateControl.modify(BOTASAURUS_SCRAPER_URL: 'http://127.0.0.1:4010') do
        result = described_class.call

        expect(result.ok).to be(false)
        expect(result.checks.find { |check| check.name == :health }.detail[:error]).to include('ConnectionFailed')
      end
    end

    it 'runs sample scrape when sample_url is given', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      conn = instance_double(Faraday::Connection)
      response = instance_double(Faraday::Response, status: 200, body: '{"version":"1.2.3"}')
      allow(Faraday).to receive(:new).and_return(conn)
      allow(conn).to receive(:get).with('/health').and_return(response)
      report = instance_double(
        Html2rss::PageRecon::Diagnostics::Report,
        to_wire_h: { status: 200, articles_count: 2 }
      )
      allow(Html2rss::PageRecon::Diagnostics).to receive(:call)
        .with(url: 'https://example.com', strategy: :botasaurus)
        .and_return(report)

      ClimateControl.modify(BOTASAURUS_SCRAPER_URL: 'http://127.0.0.1:4010') do
        result = described_class.call(sample_url: 'https://example.com')

        expect(result.ok).to be(true)
        expect(result.checks.map(&:name)).to include(:sample_scrape)
        expect(result.checks.last.detail).to include(articles_count: 2)
      end
    end

    it 'fails when sample scrape returns a bad status', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      conn = instance_double(Faraday::Connection)
      response = instance_double(Faraday::Response, status: 200, body: '{"version":"1.2.3"}')
      allow(Faraday).to receive(:new).and_return(conn)
      allow(conn).to receive(:get).with('/health').and_return(response)
      report = instance_double(
        Html2rss::PageRecon::Diagnostics::Report,
        to_wire_h: { status: 403, articles_count: 0 }
      )
      allow(Html2rss::PageRecon::Diagnostics).to receive(:call).and_return(report)

      ClimateControl.modify(BOTASAURUS_SCRAPER_URL: 'http://127.0.0.1:4010') do
        result = described_class.call(sample_url: 'https://example.com')

        expect(result.ok).to be(false)
        expect(result.message).to eq('Sample scrape failed.')
      end
    end

    it 'fails when sample scrape raises', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
      conn = instance_double(Faraday::Connection)
      response = instance_double(Faraday::Response, status: 200, body: '{"version":"1.2.3"}')
      allow(Faraday).to receive(:new).and_return(conn)
      allow(conn).to receive(:get).with('/health').and_return(response)
      allow(Html2rss::PageRecon::Diagnostics).to receive(:call)
        .and_raise(StandardError, 'scrape timeout')

      ClimateControl.modify(BOTASAURUS_SCRAPER_URL: 'http://127.0.0.1:4010') do
        result = described_class.call(sample_url: 'https://example.com')

        expect(result.ok).to be(false)
        expect(result.checks.last.detail[:error]).to include('scrape timeout')
      end
    end
  end
end
