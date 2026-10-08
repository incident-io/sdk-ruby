# frozen_string_literal: true

module IncidentIo
  # The release workflow sets this before building, so it tracks whatever we
  # last published. Listed in .openapi-generator-ignore so regeneration can't
  # reset it.
  VERSION = "2.13.0"
end
