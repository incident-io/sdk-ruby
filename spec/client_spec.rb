# frozen_string_literal: true

# Behaviour the generated client depends on us for: each example covers a
# change made by scripts/prepare_spec.py, scripts/fix_generated.py or the
# generator options in the Makefile, so a regression in one of them fails here
# rather than on a customer's machine.

RSpec.describe "the generated client" do
  let(:actions) { IncidentIo::ActionsV3Api.new }

  describe "requests" do
    it "authenticates with the configured key and identifies the SDK" do
      stub = stub_request(:get, "#{BASE_URL}/v3/actions/01ACTION")
        .with(headers: {
          "Authorization" => "Bearer test-key",
          "User-Agent" => "incident-io-sdk-ruby/#{IncidentIo::VERSION}",
        })
        .to_return(json_response(200, { action: action }))

      actions.actions_v3_show("01ACTION")

      expect(stub).to have_been_requested
    end

    it "escapes path parameters" do
      stub = stub_request(:get, "#{BASE_URL}/v3/actions/a%2Fb")
        .to_return(json_response(200, { action: action }))

      actions.actions_v3_show("a/b")

      expect(stub).to have_been_requested
    end

    # Goa reads the operator from between the first pair of brackets, so the
    # trailing [] Faraday adds to an array value is accepted.
    it "encodes operator filters as nested query parameters" do
      stub = stub_request(:get, "#{BASE_URL}/v2/incidents")
        .with(query: "status_category%5Bone_of%5D%5B%5D=live")
        .to_return(json_response(200, { incidents: [] }))

      IncidentIo::IncidentsV2Api.new.incidents_v2_list(status_category: { one_of: ["live"] })

      expect(stub).to have_been_requested
    end

    it "sends a value outside the documented enum rather than rejecting it" do
      stub = stub_request(:get, "#{BASE_URL}/v2/incidents")
        .with(query: { sort_by: "a_future_order" })
        .to_return(json_response(200, { incidents: [] }))

      IncidentIo::IncidentsV2Api.new.incidents_v2_list(sort_by: "a_future_order")

      expect(stub).to have_been_requested
    end
  end

  describe "responses" do
    it "keeps an enum value this build does not know about" do
      stub_request(:get, "#{BASE_URL}/v3/actions/01ACTION")
        .to_return(json_response(200, { action: action(status: "a_future_status") }))

      expect(actions.actions_v3_show("01ACTION").action.status).to eq("a_future_status")
    end

    it "ignores a field this build does not know about" do
      stub_request(:get, "#{BASE_URL}/v3/actions/01ACTION")
        .to_return(json_response(200, { action: action(a_future_field: 1) }))

      expect(actions.actions_v3_show("01ACTION").action.description).to eq("Restart the thing")
    end
  end

  describe "errors" do
    {
      400 => IncidentIo::BadRequestError,
      401 => IncidentIo::AuthenticationError,
      403 => IncidentIo::PermissionDeniedError,
      404 => IncidentIo::NotFoundError,
      409 => IncidentIo::ConflictError,
      422 => IncidentIo::UnprocessableEntityError,
      429 => IncidentIo::RateLimitError,
      500 => IncidentIo::ServerError,
      503 => IncidentIo::ServerError,
    }.each do |status, klass|
      it "raises #{klass} for #{status}" do
        stub_request(:get, "#{BASE_URL}/v3/actions/01ACTION")
          .to_return(json_response(status, error_body(status, "some_error")))

        expect { actions.actions_v3_show("01ACTION") }.to raise_error(klass) { |error|
          expect(error).to be_a(IncidentIo::ApiError)
          expect(error.code).to eq(status)
          expect(error.request_id).to eq("req-#{status}")
          expect(error.error_type).to eq("some_error")
          expect(error.errors.first["message"]).to eq("something about some_error")
        }
      end
    end

    it "raises ApiError itself for a status without its own class" do
      stub_request(:get, "#{BASE_URL}/v3/actions/01ACTION")
        .to_return(json_response(418, error_body(418, "teapot")))

      expect { actions.actions_v3_show("01ACTION") }.to raise_error(IncidentIo::ApiError) { |error|
        expect(error.class).to eq(IncidentIo::ApiError)
        expect(error.request_id).to eq("req-418")
      }
    end

    it "copes with an error body that is not JSON" do
      stub_request(:get, "#{BASE_URL}/v3/actions/01ACTION")
        .to_return(status: 502, body: "<html>Bad gateway</html>", headers: { "Content-Type" => "text/html" })

      expect { actions.actions_v3_show("01ACTION") }.to raise_error(IncidentIo::ServerError) { |error|
        expect(error.request_id).to be_nil
        expect(error.errors).to eq([])
      }
    end

    it "reads Retry-After from a rate-limited response" do
      stub_request(:get, "#{BASE_URL}/v3/actions/01ACTION")
        .to_return(json_response(429, error_body(429, "too_many_requests"), "Retry-After" => "7"))

      expect { actions.actions_v3_show("01ACTION") }.to raise_error(IncidentIo::RateLimitError) { |error|
        expect(error.retry_after).to eq(7)
      }
    end

    it "raises ApiError with no code when the connection fails" do
      stub_request(:get, "#{BASE_URL}/v3/actions/01ACTION").to_timeout

      expect { actions.actions_v3_show("01ACTION") }.to raise_error(IncidentIo::ApiError) { |error|
        expect(error.code).to be_nil
      }
    end
  end

  describe "deprecated endpoints" do
    let(:deprecated) { IncidentIo::ActionsV2Api.new }

    before do
      stub_request(:get, "#{BASE_URL}/v2/actions").to_return(json_response(200, { actions: [] }))
    end

    around do |example|
      previous = Warning[:deprecated]
      example.run
    ensure
      Warning[:deprecated] = previous
    end

    it "warns once per call, naming the caller's line, when deprecation warnings are on" do
      Warning[:deprecated] = true

      expect { deprecated.actions_v2_list }
        .to output(/\A#{Regexp.escape(__FILE__)}:\d+: warning: GET \/v2\/actions is deprecated/).to_stderr
      expect { deprecated.actions_v2_list_with_http_info }
        .to output(/\A#{Regexp.escape(__FILE__)}:\d+: warning: GET \/v2\/actions is deprecated[^\n]*\n\z/).to_stderr
    end

    it "is silent when deprecation warnings are off, as they are by default" do
      Warning[:deprecated] = false

      expect { deprecated.actions_v2_list }.not_to output.to_stderr
    end

    it "is marked for YARD" do
      source = File.read(IncidentIo::ActionsV2Api.instance_method(:actions_v2_list).source_location.first)

      expect(source).to include("# @deprecated GET /v2/actions is deprecated and will be removed.\n    def actions_v2_list(")
    end
  end
end
