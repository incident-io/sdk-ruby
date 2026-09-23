# frozen_string_literal: true

require "incident_io"
require "json"
require "webmock/rspec"

# A real HTTP stub rather than a mocked ApiClient, so the specs exercise the
# generated request building, Faraday, and response parsing end to end.
WebMock.disable_net_connect!

BASE_URL = IncidentIo::Configuration.default.base_url

module SpecHelpers
  def json_response(status, body, headers = {})
    { status: status, body: JSON.generate(body), headers: { "Content-Type" => "application/json" }.merge(headers) }
  end

  def error_body(status, type)
    {
      type: type,
      status: status,
      request_id: "req-#{status}",
      errors: [{ code: type, message: "something about #{type}" }],
    }
  end

  def action(overrides = {})
    {
      id: "01ACTION",
      incident_id: "01INCIDENT",
      creator: {},
      description: "Restart the thing",
      status: "outstanding",
      created_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-01-01T00:00:00Z",
    }.merge(overrides)
  end
end

RSpec.configure do |config|
  config.include SpecHelpers
  config.disable_monkey_patching!
  config.order = :random

  config.before do
    IncidentIo.configure { |c| c.access_token = "test-key" }
  end
end
