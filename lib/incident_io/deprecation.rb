# frozen_string_literal: true

# Hand-written. scripts/fix_generated.py calls this from every endpoint the
# schema marks deprecated, because the generator ignores the flag.

module IncidentIo
  module Deprecation
    LIB_DIR = File.expand_path("..", __dir__)

    # Emits a deprecation warning pointing at the caller's own line.
    #
    # Category :deprecated, so Ruby shows it only when deprecation warnings are
    # on (`ruby -W:deprecated`, or `Warning[:deprecated] = true`), the same as
    # its own. They are off by default.
    #
    # Each endpoint has two entry points and the plain one calls the
    # _with_http_info one, so a `uplevel:` of 1 would blame the SDK for half of
    # all calls. Skip every frame inside the gem instead.
    def self.warn(endpoint)
      return unless Warning[:deprecated]

      location = caller_locations.find { |frame| !frame.path.to_s.start_with?(LIB_DIR) }
      where = location ? "#{location.path}:#{location.lineno}: " : ""
      Kernel.warn(
        "#{where}warning: #{endpoint} is deprecated and will be removed. " \
        "See https://api-docs.incident.io/ for the replacement.",
        category: :deprecated,
      )
    end
  end
end
