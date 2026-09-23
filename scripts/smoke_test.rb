# frozen_string_literal: true

# Check the SDK against the live API.
#
# The specs stub HTTP, so they prove the client builds requests and parses
# responses the way we think the API behaves. This proves it against the API
# itself: auth, URL building, deserialising real responses, the pagination
# cursor, the error classes and nested filter encoding.
#
# Read-only throughout. It never creates or changes anything.
#
#   INCIDENT_API_KEY=inc_... make smoke

require "incident_io"

token = ENV.fetch("INCIDENT_API_KEY") { abort "Set INCIDENT_API_KEY first. A viewer-scoped key is enough." }
base_url = ENV.fetch("INCIDENT_BASE_URL", "https://api.incident.io")

IncidentIo.configure do |config|
  config.access_token = token
  uri = URI(base_url)
  config.scheme = uri.scheme
  config.host = uri.host
end

puts "Testing against #{base_url}\n\n"
failures = []

check = lambda do |name, &block|
  detail = block.call
  puts "ok    #{name}#{" (#{detail})" if detail}"
rescue StandardError => e
  failures << name
  puts "FAIL  #{name}\n        #{e.class}: #{e.message.lines.first}"
end

incidents = IncidentIo::IncidentsV2Api.new

check.call("authenticates and lists incidents") do
  page = incidents.incidents_v2_list(page_size: 5)
  "#{page.incidents.size} incidents"
end

check.call("follows the pagination cursor") do
  first = incidents.incidents_v2_list(page_size: 1)
  after = first.pagination_meta&.after
  next "only one page" if after.nil?

  second = incidents.incidents_v2_list(page_size: 1, after: after)
  raise "second page repeated the first" if second.incidents.map(&:id) == first.incidents.map(&:id)

  "two distinct pages"
end

check.call("encodes an operator filter the API accepts") do
  page = incidents.incidents_v2_list(page_size: 5, status_category: { one_of: ["closed"] })
  others = page.incidents.reject { |incident| incident.incident_status.category == "closed" }
  raise "filter ignored: got #{others.map(&:reference).join(', ')}" if others.any?

  "#{page.incidents.size} closed incidents"
end

check.call("parses a response with enum-typed fields") do
  severities = IncidentIo::SeveritiesV1Api.new.severities_v1_list.severities
  "#{severities.size} severities"
end

check.call("raises NotFoundError with a request ID for a missing resource") do
  incidents.incidents_v2_show("01NOTAREALINCIDENTID000000")
  raise "expected a 404"
rescue IncidentIo::NotFoundError => e
  raise "no request_id on the error" if e.request_id.to_s.empty?

  "request_id #{e.request_id}"
end

check.call("raises AuthenticationError for a bad key") do
  config = IncidentIo::Configuration.default.dup
  config.access_token = "not-a-real-key"
  IncidentIo::IncidentsV2Api.new(IncidentIo::ApiClient.new(config)).incidents_v2_list(page_size: 1)
  raise "expected a 401"
rescue IncidentIo::AuthenticationError => e
  "#{e.code} #{e.error_type}"
end

puts
if failures.any?
  abort "#{failures.size} check(s) failed"
end
puts "All checks passed."
