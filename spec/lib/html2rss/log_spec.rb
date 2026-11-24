# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::Log do
  describe '.event' do
    let(:io) { StringIO.new }
    let(:logger) { Logger.new(io, level: Logger::DEBUG, formatter: ->(_severity, _time, _prog, message) { "#{message}\n" }) }

    before { allow(Html2rss).to receive(:logger).and_return(logger) }

    %i[debug info warn error].each do |level|
      it "emits the event_name first, then the fields in order, at #{level}", :aggregate_failures do
        result = described_class.event(level, 'x.y', host: 'example.com', count: 2)

        expect(result).to be(true)
        expect(io.string).to eq("{\"event_name\":\"x.y\",\"host\":\"example.com\",\"count\":2}\n")
      end
    end

    it 'routes each level through its own Log method', :aggregate_failures do
      %i[debug info warn error].each do |level|
        allow(described_class).to receive(level)
        described_class.event(level, 'x')

        expect(described_class).to have_received(level).with('{"event_name":"x"}').once
      end
    end

    it 'does not build the debug payload while debug is off', :aggregate_failures do
      logger.level = Logger::INFO
      field = instance_double(Object)
      allow(field).to receive(:to_json)

      expect(described_class.event(:debug, 'x', field:)).to be(true)
      expect(field).not_to have_received(:to_json)
    end

    it 'rejects an unknown level' do
      expect { described_class.event(:fatal, 'x') }.to raise_error(described_class::UnknownLevelError, /:fatal/)
    end

    it 'still emits info and warn when debug is off', :aggregate_failures do
      logger.level = Logger::INFO

      described_class.event(:info, 'a')

      expect(io.string).to eq("{\"event_name\":\"a\"}\n")
    end
  end
end
