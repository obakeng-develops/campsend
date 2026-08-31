# Shared response shapes, so every tool answers the same way.
#
# Content is the JSON text an older client reads; structured_content is the same
# payload for a client that understands it.
module Agent::Response
  module_function

  def ok(payload)
    WideEvent.add(mcp_outcome: "ok")
    MCP::Tool::Response.new([ { type: "text", text: payload.to_json } ], structured_content: payload)
  end

  def failure(message)
    WideEvent.add(mcp_outcome: "tool_error", mcp_error: message)
    MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
  end
end
