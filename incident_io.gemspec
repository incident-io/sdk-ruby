# frozen_string_literal: true

require_relative "lib/incident_io/version"

Gem::Specification.new do |spec|
  # The published name, and the only place it is written; see "The gem name"
  # in CONTRIBUTING.md. The library is `require "incident_io"` and the module
  # `IncidentIo`; lib/incident_io_api.rb exists so Bundler.require also works.
  spec.name = "incident_io_api"
  spec.version = IncidentIo::VERSION
  spec.summary = "Ruby client for the incident.io API"
  spec.description = "Generated from incident.io's published OpenAPI schema: " \
                     "a method for every API endpoint, and a class for every request and response."
  spec.authors = ["incident.io"]
  spec.email = ["support@incident.io"]
  spec.homepage = "https://github.com/incident-io/sdk-ruby"
  spec.license = "MIT"

  # Faraday 2 sets the same floor. Tested on every minor from here to the
  # newest in CI; see the matrix in .github/workflows/test.yml.
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "source_code_uri" => "https://github.com/incident-io/sdk-ruby",
    "changelog_uri" => "https://github.com/incident-io/sdk-ruby/releases",
    "documentation_uri" => "https://api-docs.incident.io/",
    "bug_tracker_uri" => "https://github.com/incident-io/sdk-ruby/issues",
  }

  # An allowlist. The generator's own gemspec packages `find *`, which would
  # ship the 7MB schema, 1,200 generated markdown files and our tooling.
  spec.files = Dir["lib/**/*.rb"] + ["README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # What the generated faraday client requires. Faraday 2 rather than the
  # generator's `>= 1.0.1`: 1.x bundled multipart itself, so the separate
  # faraday-multipart the generated code requires is a 2.x arrangement.
  spec.add_dependency "faraday", ">= 2.0", "< 3"
  spec.add_dependency "faraday-multipart", "~> 1.0"
  spec.add_dependency "marcel", ">= 1.0", "< 3"
end
