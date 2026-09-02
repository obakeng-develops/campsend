require "test_helper"

class ExtensionSeamsTest < ActionDispatch::IntegrationTest
  test "a stock install renders no extension head partials and allows no extra origins" do
    assert_empty Rails.configuration.x.extension_head_partials
    assert_empty Rails.configuration.x.extension_script_src
    assert_empty Rails.configuration.x.extension_connect_src

    get new_session_path

    assert_response :success
    policy = response.headers["Content-Security-Policy"]
    assert_match(/script-src 'self'/, policy)
    assert_no_match(/posthog|analytics/, policy)
  end

  test "a distribution can put a tag in the head" do
    get new_session_path
    baseline = response.body.scan("wordmark-logo__icon").size

    Rails.configuration.x.extension_head_partials << "shared/wordmark"
    get new_session_path

    assert_response :success
    assert_equal baseline + 1, response.body.scan("wordmark-logo__icon").size
  ensure
    Rails.configuration.x.extension_head_partials.clear
  end
end
