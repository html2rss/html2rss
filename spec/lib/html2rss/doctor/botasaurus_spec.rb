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
      end
    end
  end
end
