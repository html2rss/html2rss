# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Html2rss::CLI::ErrorReporting do
  let(:host) do
    Class.new do
      def invoke_command(command, *)
        raise @error if command == :x

        :ok
      end

      def initialize(error) = @error = error
    end.prepend(described_class)
  end

  def report(error)
    host.new(error).invoke_command(:x)
  end

  it 're-raises a ContractError untouched', :aggregate_failures do
    error = Html2rss::ContractError.new('bug')

    expect { report(error) }.to(raise_error { |raised| expect(raised).to be(error) })
  end

  it 'turns a plain Html2rss::Error into a Thor::Error with its message', :aggregate_failures do
    expect { report(Html2rss::Error.new('boom')) }.to raise_error(Thor::Error) { |raised|
      expect(raised.message).to eq('boom')
    }
  end

  it 'hints at --max-redirects for RedirectLimitReached' do
    expect { report(Html2rss::RequestService::RedirectLimitReached.new('too many')) }
      .to raise_error(Thor::Error, 'too many. already retried the last redirect hop once; ' \
                                   'retry with higher --max-redirects or use the final URL directly.')
  end

  it 'hints at --max-requests for RequestBudgetExceeded' do
    expect { report(Html2rss::RequestService::RequestBudgetExceeded.new('budget')) }
      .to raise_error(Thor::Error, 'budget. retry with higher --max-requests or ' \
                                   'increase request.max_requests in config.')
  end
end
