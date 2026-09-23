# frozen_string_literal: true

# Hand-written. The generated client raises `ApiError.new(code: status, ...)`
# for every failed request. Overriding ApiError.new here turns that into the
# subclass for the status, so callers can rescue a 404 without inspecting
# codes. Every class here inherits from ApiError, so `rescue IncidentIo::ApiError`
# still catches everything it did before.

require "json"
require "incident_io/api_error"

module IncidentIo
  class ApiError
    # The generator only ever calls ApiError.new, with a hash carrying the
    # status as `code:` for an HTTP failure or a message string for a network
    # one. Subclasses and message strings construct normally.
    def self.new(arg = nil)
      return super unless equal?(ApiError) && arg.is_a?(Hash)

      klass = for_status(arg[:code])
      klass.equal?(ApiError) ? super : klass.new(arg)
    end

    # The subclass for a response status. A status without its own class gets
    # ApiError itself.
    def self.for_status(status)
      case status
      when 400 then BadRequestError
      when 401 then AuthenticationError
      when 403 then PermissionDeniedError
      when 404 then NotFoundError
      when 409 then ConflictError
      when 422 then UnprocessableEntityError
      when 429 then RateLimitError
      when 500.. then ServerError
      else ApiError
      end
    end

    # The ID incident.io assigned to the failed request. Include it when you
    # contact support.
    def request_id
      error_body["request_id"]
    end

    # The error type from the response body, such as "validation_error".
    def error_type
      error_body["type"]
    end

    # The individual errors from the response body, each a Hash with "code",
    # "message" and, for validation errors, a "source" naming the field.
    def errors
      error_body.fetch("errors", [])
    end

    private

    # Parsed on demand rather than in initialize, so that a body that is not
    # JSON (a proxy's HTML error page) costs nothing unless someone asks.
    def error_body
      return @error_body if defined?(@error_body)

      parsed = response_body.is_a?(String) ? JSON.parse(response_body) : response_body
      @error_body = parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      @error_body = {}
    end
  end

  # 400: the request was malformed.
  class BadRequestError < ApiError; end

  # 401: the API key is missing or invalid.
  class AuthenticationError < ApiError; end

  # 403: the API key is valid but lacks the permission this endpoint needs.
  class PermissionDeniedError < ApiError; end

  # 404: the resource does not exist, or this key cannot see it.
  class NotFoundError < ApiError; end

  # 409: the request conflicts with the resource's current state.
  class ConflictError < ApiError; end

  # 422: the request was well-formed but failed validation. #errors names the
  # fields.
  class UnprocessableEntityError < ApiError; end

  # 429: rate limited.
  class RateLimitError < ApiError
    # Seconds to wait before retrying, from the Retry-After header, or nil.
    def retry_after
      value = response_headers && response_headers["Retry-After"]
      Integer(value, exception: false) if value
    end
  end

  # 5xx: something went wrong on incident.io's side.
  class ServerError < ApiError; end
end
