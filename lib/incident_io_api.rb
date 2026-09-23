# frozen_string_literal: true

# The gem is published as incident_io_api, and Bundler.require loads a gem by
# its own name. Without this file that require would fail silently and leave
# IncidentIo undefined in a Rails app. The library itself is `incident_io`.
require_relative "incident_io"
