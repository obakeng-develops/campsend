module Mcp
  # MCP over HTTP. One JSON-RPC request in, one JSON response out.
  #
  # The gem's Streamable HTTP transport also does SSE, sessions and resumability.
  # None of the tools stream or notify, and the spec lets a server answer with
  # application/json, so this stays a plain POST.
  class ServerController < ApplicationController
    SERVER_NAME = "campsend"
    TOOLS = [ ListDeliveriesTool, GetDeliveryTool ].freeze

    allow_unauthenticated_access
    skip_forgery_protection
    before_action :require_api_token
    rate_limit to: 120, within: 1.hour, by: -> { @api_token.id }

    def create
      body = request.body.read
      response_json = build_server.handle_json(body)

      WideEvent.add(mcp_method: method_from(body))

      # A JSON-RPC notification has no response, which is a 202 with no body.
      return head :accepted if response_json.nil?

      render json: response_json
    end

    private
      def require_api_token
        @api_token = ApiToken.authenticate(bearer_token)
        return if @api_token

        WideEvent.add(outcome: "mcp_unauthorized")
        render json: unauthorized_body, status: :unauthorized
      end

      # Never a redirect to the sign-in page, which is what ApplicationController
      # would otherwise do and what a client cannot act on.
      def require_authentication
        require_api_token
      end

      def bearer_token
        request.authorization.to_s[/\ABearer (.+)\z/, 1]
      end

      def unauthorized_body
        { jsonrpc: "2.0", id: nil, error: { code: JsonRpcHandler::ErrorCode::INVALID_REQUEST, message: "Provide a Campsend API token as a bearer token." } }
      end

      def build_server
        WideEvent.add(user_id: @api_token.user_id, api_token_id: @api_token.id, api_token_scope: @api_token.scope, **Campsend.policy.telemetry_for(@api_token.user))

        MCP::Server.new(
          name: SERVER_NAME,
          version: Campsend::VERSION,
          tools: TOOLS,
          server_context: { user: @api_token.user, api_token: @api_token }
        )
      end

      def method_from(body)
        JSON.parse(body)["method"]
      rescue JSON::ParserError
        nil
      end
  end
end
