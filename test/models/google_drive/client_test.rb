require "test_helper"

class GoogleDrive::ClientTest < ActiveSupport::TestCase
  test "allows redirects only to Google download hosts" do
    client = GoogleDrive::Client.new

    assert client.send(:trusted_download_host?, "content.googleapis.com")
    assert client.send(:trusted_download_host?, "download.googleusercontent.com")
    assert_not client.send(:trusted_download_host?, "example.com")
    # A host that merely ends in the right characters is not a subdomain of it.
    assert_not client.send(:trusted_download_host?, "evilgoogleusercontent.com.attacker.test")
  end
end
