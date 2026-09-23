# incident.io Ruby SDK

The official Ruby SDK for the [incident.io](https://incident.io)
[public API](https://api-docs.incident.io/).

It is generated automatically from our published OpenAPI schema, so it always
tracks the live API: there is a method for every endpoint, and a class for
every request and response.

## Install

```bash
gem install incident_io_api
```

Or in your `Gemfile`:

```ruby
gem "incident_io_api"
```

The library itself is `require "incident_io"`, and everything lives under the
`IncidentIo` module.

Requires Ruby 3.0 or later.

## Quickstart

Create an API key in your incident.io dashboard under **Settings → API keys**,
then:

```ruby
require "incident_io"

IncidentIo.configure do |config|
  config.access_token = ENV.fetch("INCIDENT_API_KEY")
end

result = IncidentIo::IncidentsV2Api.new.incidents_v2_list(page_size: 25)
result.incidents.each do |incident|
  puts "#{incident.reference} #{incident.name}"
end
```

Each API resource has a class, such as `IncidentsV2Api` or `AlertsV2Api`, with
one method per endpoint. Path parameters and request bodies are positional
arguments; everything optional goes in a trailing hash:

```ruby
api = IncidentIo::IncidentsV2Api.new
incident = api.incidents_v2_show("01FDAG4SAP5TYPT98WGR2N7W91").incident
```

Every method has a `_with_http_info` twin that returns the parsed body, the
status code and the response headers:

```ruby
data, status, headers = api.incidents_v2_list_with_http_info(page_size: 25)
```

## Errors

A request that fails raises a subclass of `IncidentIo::ApiError` for the
status code:

| Status | Class |
| --- | --- |
| 400 | `IncidentIo::BadRequestError` |
| 401 | `IncidentIo::AuthenticationError` |
| 403 | `IncidentIo::PermissionDeniedError` |
| 404 | `IncidentIo::NotFoundError` |
| 409 | `IncidentIo::ConflictError` |
| 422 | `IncidentIo::UnprocessableEntityError` |
| 429 | `IncidentIo::RateLimitError` |
| 5xx | `IncidentIo::ServerError` |

Any other status raises `IncidentIo::ApiError` itself, and so do network
failures and timeouts, with a `code` of `nil`. Rescue the base class to catch
everything:

```ruby
begin
  api.incidents_v2_show("does-not-exist")
rescue IncidentIo::NotFoundError
  puts "no such incident"
rescue IncidentIo::ApiError => e
  puts "#{e.code} #{e.error_type}: #{e.errors.map { |err| err["message"] }.join(", ")}"
  puts "request ID for support: #{e.request_id}"
end
```

`RateLimitError#retry_after` gives the number of seconds from the
`Retry-After` header.

## Configuration

`IncidentIo.configure` sets the defaults every API class uses. For more than
one configuration in a process, build an `ApiClient` and pass it in:

```ruby
config = IncidentIo::Configuration.new
config.access_token = "my-api-key"
config.timeout = 30 # seconds; the default is 60

client = IncidentIo::ApiClient.new(config)
client.user_agent = "my-app/1.0.0" # identify your integration

api = IncidentIo::IncidentsV2Api.new(client)
```

`config.configure_faraday_connection { |conn| ... }` gives you the Faraday
connection, to add middleware such as retries or logging.

### Pagination

List endpoints are cursor-paginated. Read the next cursor from
`pagination_meta.after` and pass it back as `after`:

```ruby
after = nil
loop do
  page = api.incidents_v2_list(page_size: 100, after: after)
  page.incidents.each { |incident| puts incident.reference }

  after = page.pagination_meta&.after
  break if after.nil?
end
```

### Filters

Filters that take an operator are nested hashes:

```ruby
api.incidents_v2_list(status_category: { one_of: ["live"] })
```

### Enum values

Fields the API documents as an enum are plain strings in this SDK, and the
documentation lists the known values. We add values to enums as a
backwards-compatible change, and a closed enum would make every
already-installed copy of the gem fail on the first response that carried a
new one.

### Deprecated endpoints

Endpoints that incident.io has deprecated (for example the `v1` incidents and
custom fields endpoints, superseded by `v2`) remain available, but are marked
`@deprecated` in the documentation and warn when called. Ruby hides
deprecation warnings by default; run with `ruby -W:deprecated`, or set
`Warning[:deprecated] = true`, to see them.

## Versioning

Releases are cut automatically whenever the API schema changes. We use
[SemVer](https://semver.org/): additive API changes bump the minor version.
Changes that would break existing code are never released automatically; they
require a deliberate major version.

## Support

Found a bug or missing something? Please
[open an issue](https://github.com/incident-io/sdk-ruby/issues). For questions
about the API itself, see the [API docs](https://api-docs.incident.io/).

Everything under `lib/incident_io/api/` and `lib/incident_io/models/` is
generated, so please don't send PRs editing it directly; changes there come
from the upstream schema.

## License

MIT; see [LICENSE](./LICENSE).

This SDK's generated code is produced by
[OpenAPI Generator](https://openapi-generator.tech), which is licensed under
Apache-2.0.
