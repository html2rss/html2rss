# frozen_string_literal: true

RSpec.describe Html2rss::CLI, '#doctor' do
  let(:ok) { true }
  let(:result) do
    Html2rss::Doctor::Botasaurus::Result.new(
      ok:, checks: [Html2rss::Doctor::Botasaurus::Check.new(name: :env, ok: true, detail: 'set')],
      message: 'all good'
    )
  end
  let(:run_doctor) { ->(args, options = {}) { described_class.new.invoke(:doctor, args, options) } }

  before { allow(Html2rss::Doctor::Botasaurus).to receive(:call).and_return(result) }

  it 'runs the botasaurus check by default and prints the result JSON to stderr', :aggregate_failures do
    expect { run_doctor.call([]) }.to output(
      "#{JSON.pretty_generate(ok: true, message: 'all good', checks: [{ name: 'env', ok: true, detail: 'set' }])}\n"
    ).to_stderr
    expect(Html2rss::Doctor::Botasaurus).to have_received(:call).with(sample_url: nil)
  end

  it 'passes the sample url to the check', :aggregate_failures do
    expect { run_doctor.call(['botasaurus'], { sample: 'https://a.test' }) }.to output(/all good/).to_stderr
    expect(Html2rss::Doctor::Botasaurus).to have_received(:call).with(sample_url: 'https://a.test')
  end

  context 'when the check fails' do
    let(:ok) { false }

    it 'raises with the result message', :aggregate_failures do
      expect do
        run_doctor.call(['botasaurus'])
      end.to raise_error(Thor::Error, 'all good').and output(/all good/).to_stderr
    end
  end

  it 'rejects unknown check types without running anything', :aggregate_failures do
    expect { run_doctor.call(['redis']) }
      .to raise_error(Thor::Error, 'Unknown doctor type: redis. Supported: botasaurus')
    expect(Html2rss::Doctor::Botasaurus).not_to have_received(:call)
  end
end
