require "test_helper"

class TrustedProxiesTest < ActionDispatch::IntegrationTest
  # The local reverse proxy is the peer and appends the Cloudflare edge it
  # heard from, so the visitor is two hops back in the header.
  test "a request through a Cloudflare edge reports the visitor's address" do
    get root_path, headers: { "REMOTE_ADDR" => "10.0.0.5", "X-Forwarded-For" => "203.0.113.9, 172.68.140.168" }

    assert_equal "203.0.113.9", request.remote_ip
  end
end
