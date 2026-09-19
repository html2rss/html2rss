# frozen_string_literal: true

module FixtureHelpers
  def challenge_fixture(name)
    path = Pathname(File.expand_path('../../fixtures/challenge', __dir__)).join(name)
    raise "challenge fixture missing at #{path}" unless path.file?

    path.read
  end

  def load_json_state_fixture(name)
    file = File.expand_path("../../fixtures/auto_source/json_state/#{name}", __dir__)
    File.read(file)
  end
  alias load_fixture load_json_state_fixture

  def enhance_audit_response(fixture_name)
    body = File.read(File.expand_path("../../fixtures/enhance_audit/#{fixture_name}", __dir__))
    Html2rss::RequestService::Response.new(
      url: 'https://example.com/list',
      headers: { 'content-type' => 'text/html' },
      body:
    )
  end

  def probe_audit(fixture_name, selectors, time_zone: 'UTC')
    Html2rss::Test::EnhanceAudit.probe(response: enhance_audit_response(fixture_name), selectors:, time_zone:)
  end
end
